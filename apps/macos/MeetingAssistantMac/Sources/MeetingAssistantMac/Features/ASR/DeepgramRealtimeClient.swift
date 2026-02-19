import Foundation

final class DeepgramRealtimeClient: AsrClient {
    enum DeepgramError: LocalizedError {
        case invalidURL
        case missingApiKey

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid Deepgram websocket URL."
            case .missingApiKey:
                return "Deepgram API key is missing."
            }
        }
    }

    var onTranscript: ((TranscriptChunk) -> Void)?

    private let apiKey: String
    private let config: DeepgramConfig
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    init(apiKey: String, config: DeepgramConfig, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.config = config
        self.session = session
    }

    func start() async throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepgramError.missingApiKey
        }

        if task != nil {
            return
        }

        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")
        components?.queryItems = [
            URLQueryItem(name: "model", value: "nova-2"),
            URLQueryItem(name: "language", value: config.language),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "interim_results", value: config.interimEnabled ? "true" : "false"),
            URLQueryItem(name: "endpointing", value: "2000"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "diarize", value: "true"),
        ]

        guard let url = components?.url else {
            throw DeepgramError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let wsTask = session.webSocketTask(with: request)
        wsTask.resume()
        task = wsTask

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func sendPcm(_ pcm: [Int16]) async throws {
        guard let task else { return }

        var payload = Data(capacity: pcm.count * MemoryLayout<Int16>.size)
        pcm.forEach { sample in
            var littleEndian = sample.littleEndian
            withUnsafeBytes(of: &littleEndian) { bytes in
                payload.append(bytes.bindMemory(to: UInt8.self))
            }
        }

        try await task.send(.data(payload))
    }

    func stop() async {
        guard let task else { return }

        try? await task.send(.string("{\"type\":\"CloseStream\"}"))
        task.cancel(with: .normalClosure, reason: nil)
        self.task = nil
        receiveTask?.cancel()
        receiveTask = nil
    }

    private func receiveLoop() async {
        guard let task else { return }

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case let .string(text):
                    if let chunk = parseTranscript(payload: text) {
                        onTranscript?(chunk)
                    }
                case let .data(data):
                    if let text = String(data: data, encoding: .utf8),
                       let chunk = parseTranscript(payload: text)
                    {
                        onTranscript?(chunk)
                    }
                @unknown default:
                    break
                }
            } catch {
                break
            }
        }
    }

    private func parseTranscript(payload: String) -> TranscriptChunk? {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "Results",
              let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let first = alternatives.first,
              let transcript = first["transcript"] as? String
        else {
            return nil
        }

        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return nil
        }

        let isFinal = (json["is_final"] as? Bool) ?? false
        return TranscriptChunk(text: text, isFinal: isFinal, provider: .deepgram)
    }
}
