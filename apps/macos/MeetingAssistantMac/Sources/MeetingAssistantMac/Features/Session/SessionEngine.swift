import Foundation

final class SessionEngine {
    struct StartInput {
        var settings: SpeechPipelineSettings
        var deepgram: DeepgramConfig
        var aliyun: AliyunConfig
        var microsoft: MicrosoftTranslatorConfig
        var secrets: ProviderSecretSnapshot
    }

    var onTranscript: ((TranscriptChunk) -> Void)?
    var onTranslation: ((TranslationChunk) -> Void)?
    var onStatus: ((RuntimeStatus) -> Void)?
    var onMessage: ((String) -> Void)?

    private var systemAudio: SystemAudioCaptureService?
    private var microphoneAudio: MicrophoneCaptureService?
    private var primaryClient: AsrClient?
    private var secondaryClient: AsrClient?
    private var textTranslator: TextTranslator?
    private var translationDebounceTask: Task<Void, Never>?

    private var latestSystemChunk: [Int16] = []
    private var latestMicrophoneChunk: [Int16] = []
    private var lastInterimTranslationSource: String = ""
    private var lastFinalTranslationSource: String = ""

    private let audioQueue = DispatchQueue(label: "meeting-assistant.session-audio", qos: .userInitiated)
    private var currentStatus = RuntimeStatus()

    func start(_ input: StartInput) async {
        await stop(silently: true)

        publish(
            status: RuntimeStatus(
                sessionState: .starting,
                permissionState: .unknown,
                activeProviders: [],
                warningCode: nil
            ),
            message: "Starting live session..."
        )

        do {
            let clients = try buildClients(input)
            primaryClient = clients.primary
            secondaryClient = clients.secondary
            textTranslator = clients.translator

            try await primaryClient?.start()
            try await secondaryClient?.start()

            var permissionState: PermissionState = .granted
            var activeSourceMode = input.settings.audioSourceMode

            switch input.settings.audioSourceMode {
            case .system:
                do {
                    try await startSystemAudioOnly()
                } catch {
                    permissionState = .fallbackMicrophone
                    activeSourceMode = .microphone
                    publish(message: "System audio unavailable. Fallback to microphone mode.")
                    try await startMicrophoneOnly()
                }

            case .microphone:
                try await startMicrophoneOnly()

            case .mixed:
                do {
                    try await startMixedAudio()
                } catch {
                    permissionState = .fallbackMicrophone
                    activeSourceMode = .microphone
                    publish(message: "System audio permission denied. Running with microphone only.")
                    try await startMicrophoneOnly()
                }
            }

            let providers = activeProviders(primary: primaryClient, secondary: secondaryClient, translator: textTranslator)
            let warningCode = activeSourceMode == .microphone && input.settings.audioSourceMode != .microphone
                ? "SCREEN_PERMISSION_FALLBACK"
                : nil

            publish(
                status: RuntimeStatus(
                    sessionState: .running,
                    permissionState: permissionState,
                    activeProviders: providers,
                    warningCode: warningCode
                ),
                message: "Live session running (\(activeSourceMode.rawValue))."
            )
        } catch {
            publish(
                status: RuntimeStatus(
                    sessionState: .error,
                    permissionState: .unknown,
                    activeProviders: [],
                    warningCode: "SESSION_START_FAILED"
                ),
                message: detailedStartError(error, input: input)
            )
            await stop(silently: true)
        }
    }

    func stop(silently: Bool = false) async {
        if silently {
            publishStatus(
                RuntimeStatus(
                    sessionState: .stopping,
                    permissionState: currentStatus.permissionState,
                    activeProviders: currentStatus.activeProviders,
                    warningCode: currentStatus.warningCode
                )
            )
        } else {
            publish(status: RuntimeStatus(sessionState: .stopping), message: "Stopping session...")
        }

        await systemAudio?.stop()
        await microphoneAudio?.stop()
        systemAudio = nil
        microphoneAudio = nil

        await primaryClient?.stop()
        await secondaryClient?.stop()
        primaryClient = nil
        secondaryClient = nil
        textTranslator = nil
        translationDebounceTask?.cancel()
        translationDebounceTask = nil

        latestSystemChunk = []
        latestMicrophoneChunk = []
        lastInterimTranslationSource = ""
        lastFinalTranslationSource = ""

        let idleStatus = RuntimeStatus(sessionState: .idle, permissionState: .unknown, activeProviders: [], warningCode: nil)
        if silently {
            publishStatus(idleStatus)
        } else {
            publish(status: idleStatus, message: "Session stopped.")
        }
    }
}

private extension SessionEngine {
    typealias ClientBundle = (primary: AsrClient, secondary: AsrClient?, translator: TextTranslator?)

    func buildClients(_ input: StartInput) throws -> ClientBundle {
        switch input.settings.asrProvider {
        case .deepgram:
            guard let deepgramKey = input.secrets.deepgramApiKey,
                  !deepgramKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw NSError(domain: "SessionEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Deepgram API key is not configured"])
            }

            let deepgramClient = DeepgramRealtimeClient(apiKey: deepgramKey, config: input.deepgram)
            let translator = try buildTextTranslator(input)
            deepgramClient.onTranscript = { [weak self] chunk in
                self?.forwardTranscript(
                    chunk,
                    translator: translator,
                    sourceLanguage: input.aliyun.sourceLanguage,
                    targetLanguage: input.aliyun.targetLanguage
                )
            }

            if input.settings.translationEnabled, input.settings.translationProvider == .aliyun {
                guard let accessKeyId = input.secrets.aliyunAccessKeyId,
                      let accessKeySecret = input.secrets.aliyunAccessKeySecret,
                      let appKey = input.secrets.aliyunAppKey
                else {
                    throw NSError(domain: "SessionEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Aliyun credentials are required when translation provider is Aliyun"])
                }

                let translationClient = AliyunRealtimeClient(
                    accessKeyId: accessKeyId,
                    accessKeySecret: accessKeySecret,
                    appKey: appKey,
                    sourceLanguage: input.aliyun.sourceLanguage,
                    targetLanguage: input.aliyun.targetLanguage,
                    captureTranscript: false
                )
                translationClient.onTranslation = { [weak self] chunk in
                    DispatchQueue.main.async { self?.onTranslation?(chunk) }
                }
                return (deepgramClient, translationClient, translator)
            }
            return (deepgramClient, nil, translator)

        case .aliyun:
            guard let accessKeyId = input.secrets.aliyunAccessKeyId,
                  let accessKeySecret = input.secrets.aliyunAccessKeySecret,
                  let appKey = input.secrets.aliyunAppKey
            else {
                throw NSError(domain: "SessionEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Aliyun credentials are incomplete"])
            }

            let aliyunClient = AliyunRealtimeClient(
                accessKeyId: accessKeyId,
                accessKeySecret: accessKeySecret,
                appKey: appKey,
                sourceLanguage: input.aliyun.sourceLanguage,
                targetLanguage: input.aliyun.targetLanguage,
                captureTranscript: true
            )
            let translator = try buildTextTranslator(input)
            aliyunClient.onTranscript = { [weak self] chunk in
                self?.forwardTranscript(
                    chunk,
                    translator: translator,
                    sourceLanguage: input.aliyun.sourceLanguage,
                    targetLanguage: input.aliyun.targetLanguage
                )
            }
            if input.settings.translationEnabled, input.settings.translationProvider == .aliyun {
                aliyunClient.onTranslation = { [weak self] chunk in
                    DispatchQueue.main.async { self?.onTranslation?(chunk) }
                }
            }
            return (aliyunClient, nil, translator)
        }
    }

    func startSystemAudioOnly() async throws {
        let system = SystemAudioCaptureService()
        system.onPcm = { [weak self] pcm in
            self?.forwardSystemPcm(pcm)
        }
        try await system.start()
        systemAudio = system
    }

    func startMicrophoneOnly() async throws {
        let microphone = MicrophoneCaptureService()
        microphone.onPcm = { [weak self] pcm in
            self?.forwardMicrophonePcm(pcm)
        }
        try await microphone.start()
        microphoneAudio = microphone
    }

    func startMixedAudio() async throws {
        try await startSystemAudioOnly()
        do {
            try await startMicrophoneOnly()
        } catch {
            await systemAudio?.stop()
            systemAudio = nil
            throw error
        }
    }

    func buildTextTranslator(_ input: StartInput) throws -> TextTranslator? {
        guard input.settings.translationEnabled else {
            return nil
        }

        switch input.settings.translationProvider {
        case .aliyun:
            return nil
        case .microsoft:
            guard let apiKey = input.secrets.microsoftTranslatorKey,
                  !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw NSError(
                    domain: "SessionEngine",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Microsoft Translator API key is not configured"]
                )
            }
            return MicrosoftTranslatorClient(
                apiKey: apiKey,
                endpoint: input.microsoft.endpoint,
                region: input.microsoft.region
            )
        }
    }

    func forwardTranscript(
        _ chunk: TranscriptChunk,
        translator: TextTranslator?,
        sourceLanguage: String,
        targetLanguage: String
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.onTranscript?(chunk)
        }

        guard let translator else {
            return
        }

        let text = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }

        if chunk.isFinal {
            if text == lastFinalTranslationSource {
                return
            }
            lastFinalTranslationSource = text
            translationDebounceTask?.cancel()
            requestTextTranslation(
                text: text,
                isFinal: true,
                translator: translator,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
            return
        }

        if text == lastInterimTranslationSource {
            return
        }
        lastInterimTranslationSource = text
        translationDebounceTask?.cancel()
        translationDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.requestTextTranslation(
                text: text,
                isFinal: false,
                translator: translator,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
        }
    }

    func requestTextTranslation(
        text: String,
        isFinal: Bool,
        translator: TextTranslator,
        sourceLanguage: String,
        targetLanguage: String
    ) {
        let translationHandler = onTranslation
        let messageHandler = onMessage

        Task(priority: .userInitiated) {
            do {
                let translated = try await translator.translate(
                    text: text,
                    from: sourceLanguage,
                    to: targetLanguage
                )
                guard !translated.isEmpty else { return }
                let chunk = TranslationChunk(
                    text: translated,
                    isFinal: isFinal,
                    provider: .microsoft
                )
                DispatchQueue.main.async {
                    translationHandler?(chunk)
                }
            } catch {
                let message = "Translation error: \(error.localizedDescription)"
                DispatchQueue.main.async {
                    messageHandler?(message)
                }
            }
        }
    }

    func forwardSystemPcm(_ pcm: [Int16]) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            latestSystemChunk = pcm
            if microphoneAudio == nil {
                dispatchPcm(pcm)
            } else {
                dispatchPcm(PcmMixer.mix(system: latestSystemChunk, microphone: latestMicrophoneChunk))
            }
        }
    }

    func forwardMicrophonePcm(_ pcm: [Int16]) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            latestMicrophoneChunk = pcm
            if systemAudio == nil {
                dispatchPcm(pcm)
            } else {
                dispatchPcm(PcmMixer.mix(system: latestSystemChunk, microphone: latestMicrophoneChunk))
            }
        }
    }

    func dispatchPcm(_ pcm: [Int16]) {
        guard !pcm.isEmpty else { return }

        let primary = primaryClient
        let secondary = secondaryClient

        Task.detached(priority: .userInitiated) {
            if let primary {
                try? await primary.sendPcm(pcm)
            }
            if let secondary {
                try? await secondary.sendPcm(pcm)
            }
        }
    }

    func activeProviders(primary: AsrClient?, secondary: AsrClient?, translator: TextTranslator?) -> [String] {
        var values: [String] = []
        if primary is DeepgramRealtimeClient {
            values.append("deepgram")
        }
        if primary is AliyunRealtimeClient {
            values.append("aliyun")
        }
        if secondary is AliyunRealtimeClient {
            values.append("aliyun_translation")
        }
        if translator is MicrosoftTranslatorClient {
            values.append("microsoft_translation")
        }
        return values
    }

    func detailedStartError(_ error: Error, input: StartInput) -> String {
        let nsError = error as NSError
        let hasDeepgramKey = !(input.secrets.deepgramApiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasAliyunAccessKeyId = !(input.secrets.aliyunAccessKeyId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasAliyunAccessKeySecret = !(input.secrets.aliyunAccessKeySecret?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasAliyunAppKey = !(input.secrets.aliyunAppKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasMicrosoftKey = !(input.secrets.microsoftTranslatorKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let nestedReason = (nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let nestedSuggestion = (nsError.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let aliyunCode = (nsError.userInfo["AliyunCode"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let aliyunRequestId = (nsError.userInfo["AliyunRequestId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = [
            "Failed to start session",
            "reason=\(error.localizedDescription)",
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "asr=\(input.settings.asrProvider.rawValue)",
            "audio=\(input.settings.audioSourceMode.rawValue)",
            "sourceLang=\(input.aliyun.sourceLanguage)",
            "targetLang=\(input.aliyun.targetLanguage)",
            "hasDeepgramKey=\(hasDeepgramKey)",
            "hasAliyunAK=\(hasAliyunAccessKeyId)",
            "hasAliyunSK=\(hasAliyunAccessKeySecret)",
            "hasAliyunAppKey=\(hasAliyunAppKey)",
            "translationProvider=\(input.settings.translationProvider.rawValue)",
            "hasMicrosoftKey=\(hasMicrosoftKey)",
        ]

        if let aliyunCode, !aliyunCode.isEmpty {
            parts.append("aliyunCode=\(aliyunCode)")
        }
        if let aliyunRequestId, !aliyunRequestId.isEmpty {
            parts.append("aliyunRequestId=\(aliyunRequestId)")
        }
        if let nestedReason, !nestedReason.isEmpty {
            parts.append("failureReason=\(nestedReason)")
        }
        if let nestedSuggestion, !nestedSuggestion.isEmpty {
            parts.append("suggestion=\(nestedSuggestion)")
        }
        return parts.joined(separator: " | ")
    }

    func publishStatus(_ status: RuntimeStatus) {
        currentStatus = status
        DispatchQueue.main.async { self.onStatus?(status) }
    }

    func publish(status: RuntimeStatus? = nil, message: String) {
        if let status {
            currentStatus = status
            DispatchQueue.main.async { self.onStatus?(status) }
        }
        DispatchQueue.main.async { self.onMessage?(message) }
    }
}
