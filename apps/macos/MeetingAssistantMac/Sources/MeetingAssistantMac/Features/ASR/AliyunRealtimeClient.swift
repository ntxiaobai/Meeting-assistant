import CryptoKit
import Foundation

final class AliyunRealtimeClient: AsrClient, TranslationStream {
    private enum AudioSpec {
        static let sampleRate = 16_000
        static let format = "pcm"
    }

    enum AliyunError: LocalizedError {
        case missingCredentials
        case missingTaskFields
        case invalidURL
        case invalidSourceLanguage(String)
        case invalidTargetLanguage(String)

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "Aliyun credentials are incomplete."
            case .missingTaskFields:
                return "Aliyun CreateTask response is missing required fields."
            case .invalidURL:
                return "Aliyun request URL is invalid."
            case let .invalidSourceLanguage(value):
                return "Aliyun source language is invalid: \(value). Use cn/en/yue/ja/ko/multilingual."
            case let .invalidTargetLanguage(value):
                return "Aliyun target language is invalid: \(value). Use cn/en/ja/ko/de/fr/ru."
            }
        }
    }

    var onTranscript: ((TranscriptChunk) -> Void)?
    var onTranslation: ((TranslationChunk) -> Void)?

    private let accessKeyId: String
    private let accessKeySecret: String
    private let appKey: String
    private let sourceLanguage: String
    private let targetLanguage: String
    private let captureTranscript: Bool
    private let session: URLSession

    private var taskId: String?
    private var streamTaskId: String?
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    init(
        accessKeyId: String,
        accessKeySecret: String,
        appKey: String,
        sourceLanguage: String,
        targetLanguage: String,
        captureTranscript: Bool,
        session: URLSession = .shared
    ) {
        self.accessKeyId = accessKeyId
        self.accessKeySecret = accessKeySecret
        self.appKey = appKey
        self.sourceLanguage = Self.normalizeSourceLanguage(sourceLanguage)
        self.targetLanguage = Self.normalizeTargetLanguage(targetLanguage)
        self.captureTranscript = captureTranscript
        self.session = session
    }

    func start() async throws {
        guard !accessKeyId.isEmpty, !accessKeySecret.isEmpty, !appKey.isEmpty else {
            throw AliyunError.missingCredentials
        }
        if webSocketTask != nil {
            return
        }

        let (taskId, meetingJoinURL) = try await createTask()
        self.taskId = taskId
        self.streamTaskId = UUID().uuidString

        guard let url = URL(string: meetingJoinURL) else {
            throw AliyunError.invalidURL
        }

        let wsTask = session.webSocketTask(with: url)
        wsTask.resume()
        webSocketTask = wsTask

        try await wsTask.send(.string(buildStartTranscriptionPayload(taskId: streamTaskId ?? "")))

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func sendPcm(_ pcm: [Int16]) async throws {
        guard let task = webSocketTask else { return }
        var payload = Data(capacity: pcm.count * MemoryLayout<Int16>.size)
        pcm.forEach { sample in
            var little = sample.littleEndian
            withUnsafeBytes(of: &little) { bytes in
                payload.append(bytes.bindMemory(to: UInt8.self))
            }
        }
        try await task.send(.data(payload))
    }

    func stop() async {
        guard let task = webSocketTask else { return }

        if let streamTaskId {
            try? await task.send(.string(buildStopTranscriptionPayload(taskId: streamTaskId)))
        }
        task.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        if let taskId {
            _ = try? await stopTask(taskId: taskId)
        }

        receiveTask?.cancel()
        receiveTask = nil
        self.taskId = nil
        self.streamTaskId = nil
    }

    private func receiveLoop() async {
        guard let webSocketTask else { return }

        while !Task.isCancelled {
            do {
                let message = try await webSocketTask.receive()
                switch message {
                case let .string(text):
                    parseEventPayload(text)
                case let .data(data):
                    if let text = String(data: data, encoding: .utf8) {
                        parseEventPayload(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                break
            }
        }
    }

    private func parseEventPayload(_ payload: String) {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let header = json["header"] as? [String: Any],
              let name = header["name"] as? String,
              let body = json["payload"] as? [String: Any]
        else {
            return
        }

        switch name {
        case "TranscriptionResultChanged", "SentenceBegin", "SentenceEnd":
            guard captureTranscript,
                  let text = (body["result"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else {
                return
            }
            let isFinal = name == "SentenceEnd"
            onTranscript?(TranscriptChunk(text: text, isFinal: isFinal, provider: .aliyun))

        case "ResultTranslated":
            let partial = (body["partial"] as? Bool) ?? false
            var translated = ""
            if let items = body["translate_result"] as? [[String: Any]] {
                for item in items {
                    if let text = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !text.isEmpty
                    {
                        if !translated.isEmpty { translated += " " }
                        translated += text
                    }
                }
            }

            if !translated.isEmpty {
                onTranslation?(TranslationChunk(text: translated, isFinal: !partial, provider: .aliyun))
            }

        default:
            break
        }
    }
}

private extension AliyunRealtimeClient {
    func createTask() async throws -> (String, String) {
        if !Self.allowedSourceLanguages.contains(sourceLanguage) {
            throw AliyunError.invalidSourceLanguage(sourceLanguage)
        }
        if !Self.allowedTargetLanguages.contains(targetLanguage) {
            throw AliyunError.invalidTargetLanguage(targetLanguage)
        }

        let query = ["type": "realtime"]
        let body: [String: Any] = [
            "AppKey": appKey,
            "Input": [
                "SourceLanguage": sourceLanguage,
                "Format": AudioSpec.format,
                "SampleRate": AudioSpec.sampleRate,
                "TaskKey": "task_\(Int(Date().timeIntervalSince1970))",
            ],
            "Parameters": [
                "Transcription": [
                    "OutputLevel": 2,
                ],
                "TranslationEnabled": true,
                "Translation": [
                    "OutputLevel": 2,
                    "TargetLanguages": [targetLanguage],
                ],
            ],
        ]

        let response = try await sendSignedRequest(
            method: "PUT",
            path: "/openapi/tingwu/v2/tasks",
            query: query,
            body: body
        )

        guard (200 ..< 300).contains(response.statusCode) else {
            throw buildAliyunServiceError(
                statusCode: response.statusCode,
                data: response.data,
                operation: "CreateTask"
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let data = (json["Data"] as? [String: Any]) ?? (json["data"] as? [String: Any]),
              let taskId = (data["TaskId"] as? String) ?? (data["taskId"] as? String),
              let joinURL = (data["MeetingJoinUrl"] as? String) ?? (data["meetingJoinUrl"] as? String)
        else {
            throw AliyunError.missingTaskFields
        }

        return (taskId, joinURL)
    }

    func stopTask(taskId: String) async throws {
        let query = [
            "operation": "stop",
            "type": "realtime",
        ]
        let body: [String: Any] = ["TaskId": taskId]

        let response = try await sendSignedRequest(
            method: "PUT",
            path: "/openapi/tingwu/v2/tasks",
            query: query,
            body: body
        )
        if !(200 ..< 300).contains(response.statusCode) {
            throw buildAliyunServiceError(
                statusCode: response.statusCode,
                data: response.data,
                operation: "StopTask"
            )
        }
    }

    func sendSignedRequest(
        method: String,
        path: String,
        query: [String: String],
        body: [String: Any]
    ) async throws -> (statusCode: Int, data: Data) {
        let accept = "application/json"
        let contentType = "application/json"
        let date = httpDateNow()

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let bodyString = String(data: bodyData, encoding: .utf8) ?? "{}"
        let contentMd5 = Data(Insecure.MD5.hash(data: bodyData)).base64EncodedString()
        let nonce = UUID().uuidString

        let acsHeaders: [String: String] = [
            "x-acs-signature-method": "HMAC-SHA1",
            "x-acs-signature-nonce": nonce,
            "x-acs-signature-version": "1.0",
            "x-acs-version": "2023-09-30",
        ]

        let canonicalHeaders = canonicalizedHeaders(acsHeaders)
        let canonicalResource = canonicalizedResource(path: path, query: query)
        let stringToSign = "\(method)\n\(accept)\n\(contentMd5)\n\(contentType)\n\(date)\n\(canonicalHeaders)\(canonicalResource)"

        let signature = signHmacSha1(secret: accessKeySecret, content: stringToSign)
        let authorization = "acs \(accessKeyId):\(signature)"

        guard let url = URL(string: "https://tingwu.cn-beijing.aliyuncs.com\(canonicalResource)") else {
            throw AliyunError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyString.data(using: .utf8)
        request.setValue(accept, forHTTPHeaderField: "accept")
        request.setValue(contentType, forHTTPHeaderField: "content-type")
        request.setValue(contentMd5, forHTTPHeaderField: "content-md5")
        request.setValue(date, forHTTPHeaderField: "date")
        request.setValue(authorization, forHTTPHeaderField: "authorization")

        for (key, value) in acsHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (statusCode, data)
    }

    func canonicalizedHeaders(_ headers: [String: String]) -> String {
        headers
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { "\($0.key.lowercased()):\($0.value)\n" }
            .joined()
    }

    func canonicalizedResource(path: String, query: [String: String]) -> String {
        guard !query.isEmpty else { return path }
        let sorted = query.sorted { $0.key < $1.key }
        let pairs = sorted.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return "\(path)?\(pairs)"
    }

    func signHmacSha1(secret: String, content: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<Insecure.SHA1>.authenticationCode(for: Data(content.utf8), using: key)
        return Data(signature).base64EncodedString()
    }

    func httpDateNow() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: Date())
    }

    func buildStartTranscriptionPayload(taskId: String) -> String {
        let payload: [String: Any] = [
            "header": [
                "appkey": appKey,
                "message_id": UUID().uuidString,
                "task_id": taskId,
                "namespace": "SpeechTranscriber",
                "name": "StartTranscription",
            ],
            "payload": [
                "format": AudioSpec.format,
                "sample_rate": AudioSpec.sampleRate,
                "enable_intermediate_result": true,
                "enable_inverse_text_normalization": true,
            ],
        ]

        let data = try? JSONSerialization.data(withJSONObject: payload)
        return String(data: data ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
    }

    func buildStopTranscriptionPayload(taskId: String) -> String {
        let payload: [String: Any] = [
            "header": [
                "appkey": appKey,
                "message_id": UUID().uuidString,
                "task_id": taskId,
                "namespace": "SpeechTranscriber",
                "name": "StopTranscription",
            ],
            "payload": [:],
        ]

        let data = try? JSONSerialization.data(withJSONObject: payload)
        return String(data: data ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
    }

    func buildAliyunServiceError(statusCode: Int, data: Data, operation: String) -> NSError {
        let fallbackRaw = String(data: data, encoding: .utf8) ?? "<empty>"
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return NSError(
                domain: "AliyunRealtimeClient",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "\(operation) failed: \(fallbackRaw)"]
            )
        }

        let code = (json["Code"] as? String) ?? (json["code"] as? String) ?? "UNKNOWN"
        let message = (json["Message"] as? String) ?? (json["message"] as? String) ?? fallbackRaw
        let requestId = (json["RequestId"] as? String) ?? (json["requestId"] as? String) ?? "-"

        var suggestion = "Check Aliyun Tingwu credentials and region settings."
        if code == "BRK.InvalidTenant" {
            suggestion = "Invalid tenant usually means Tingwu service is not activated/available for this account, billing issue, or AppKey and AK/SK are not under the same account in cn-beijing."
        }

        return NSError(
            domain: "AliyunRealtimeClient",
            code: statusCode,
            userInfo: [
                NSLocalizedDescriptionKey: message,
                NSLocalizedFailureReasonErrorKey: "Aliyun code=\(code), requestId=\(requestId), operation=\(operation)",
                NSLocalizedRecoverySuggestionErrorKey: suggestion,
                "AliyunCode": code,
                "AliyunRequestId": requestId,
            ]
        )
    }

    static let allowedSourceLanguages: Set<String> = [
        "cn", "en", "yue", "ja", "ko", "multilingual",
    ]

    static let allowedTargetLanguages: Set<String> = [
        "cn", "en", "ja", "ko", "de", "fr", "ru",
    ]

    static func normalizeSourceLanguage(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "zh", "zh-cn", "chinese", "中文":
            return "cn"
        case "english":
            return "en"
        case "cantonese", "粤语":
            return "yue"
        case "japanese", "日语":
            return "ja"
        case "korean", "韩语":
            return "ko"
        default:
            return normalized
        }
    }

    static func normalizeTargetLanguage(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "zh", "zh-cn", "chinese", "中文":
            return "cn"
        case "english":
            return "en"
        case "japanese", "日语":
            return "ja"
        case "korean", "韩语":
            return "ko"
        case "german", "德语":
            return "de"
        case "french", "法语":
            return "fr"
        case "russian", "俄语":
            return "ru"
        default:
            return normalized
        }
    }
}
