import Foundation

enum AsrProviderChoice: String, Codable, CaseIterable, Identifiable {
    case deepgram
    case aliyun

    var id: String { rawValue }
}

enum TranslationProviderChoice: String, Codable, CaseIterable, Identifiable {
    case aliyun
    case microsoft

    var id: String { rawValue }
}

enum VoiceprintProviderChoice: String, Codable, CaseIterable, Identifiable {
    case deepgram
    case aliyun
    case off

    var id: String { rawValue }
}

enum AudioSourceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case microphone
    case mixed

    var id: String { rawValue }
}

struct DeepgramConfig: Codable {
    var language: String
    var interimEnabled: Bool

    init(language: String = "en", interimEnabled: Bool = true) {
        self.language = language
        self.interimEnabled = interimEnabled
    }
}

struct AliyunConfig: Codable {
    var sourceLanguage: String
    var targetLanguage: String

    init(sourceLanguage: String = "en", targetLanguage: String = "cn") {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }
}

struct MicrosoftTranslatorConfig: Codable {
    var endpoint: String
    var region: String

    init(
        endpoint: String = "https://api.cognitive.microsofttranslator.com",
        region: String = ""
    ) {
        self.endpoint = endpoint
        self.region = region
    }
}

struct SpeechPipelineSettings: Codable {
    var asrProvider: AsrProviderChoice
    var translationProvider: TranslationProviderChoice
    var translationEnabled: Bool
    var voiceprintProvider: VoiceprintProviderChoice
    var voiceprintEnabled: Bool
    var audioSourceMode: AudioSourceMode

    init(
        asrProvider: AsrProviderChoice = .deepgram,
        translationProvider: TranslationProviderChoice = .microsoft,
        translationEnabled: Bool = true,
        voiceprintProvider: VoiceprintProviderChoice = .off,
        voiceprintEnabled: Bool = false,
        audioSourceMode: AudioSourceMode = .system
    ) {
        self.asrProvider = asrProvider
        self.translationProvider = translationProvider
        self.translationEnabled = translationEnabled
        self.voiceprintProvider = voiceprintProvider
        self.voiceprintEnabled = voiceprintEnabled
        self.audioSourceMode = audioSourceMode
    }

    enum CodingKeys: String, CodingKey {
        case asrProvider
        case translationProvider
        case translationEnabled
        case voiceprintProvider
        case voiceprintEnabled
        case audioSourceMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        asrProvider = try container.decodeIfPresent(AsrProviderChoice.self, forKey: .asrProvider) ?? .deepgram
        translationProvider = try container.decodeIfPresent(TranslationProviderChoice.self, forKey: .translationProvider) ?? .microsoft
        translationEnabled = try container.decodeIfPresent(Bool.self, forKey: .translationEnabled) ?? true
        voiceprintProvider = try container.decodeIfPresent(VoiceprintProviderChoice.self, forKey: .voiceprintProvider) ?? .off
        voiceprintEnabled = try container.decodeIfPresent(Bool.self, forKey: .voiceprintEnabled) ?? false
        audioSourceMode = try container.decodeIfPresent(AudioSourceMode.self, forKey: .audioSourceMode) ?? .system
    }
}

enum SessionLifecycleState: String, Codable {
    case idle
    case starting
    case running
    case stopping
    case error
}

enum PermissionState: String, Codable {
    case unknown
    case granted
    case denied
    case fallbackMicrophone
}

struct RuntimeStatus: Codable {
    var sessionState: SessionLifecycleState
    var permissionState: PermissionState
    var activeProviders: [String]
    var warningCode: String?

    init(
        sessionState: SessionLifecycleState = .idle,
        permissionState: PermissionState = .unknown,
        activeProviders: [String] = [],
        warningCode: String? = nil
    ) {
        self.sessionState = sessionState
        self.permissionState = permissionState
        self.activeProviders = activeProviders
        self.warningCode = warningCode
    }
}

struct SpeechSettingsEnvelope: Codable {
    var pipeline: SpeechPipelineSettings
    var deepgram: DeepgramConfig
    var aliyun: AliyunConfig
    var microsoft: MicrosoftTranslatorConfig

    init(
        pipeline: SpeechPipelineSettings = .init(),
        deepgram: DeepgramConfig = .init(),
        aliyun: AliyunConfig = .init(),
        microsoft: MicrosoftTranslatorConfig = .init()
    ) {
        self.pipeline = pipeline
        self.deepgram = deepgram
        self.aliyun = aliyun
        self.microsoft = microsoft
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pipeline = try container.decodeIfPresent(SpeechPipelineSettings.self, forKey: .pipeline) ?? .init()
        deepgram = try container.decodeIfPresent(DeepgramConfig.self, forKey: .deepgram) ?? .init()
        aliyun = try container.decodeIfPresent(AliyunConfig.self, forKey: .aliyun) ?? .init()
        microsoft = try container.decodeIfPresent(MicrosoftTranslatorConfig.self, forKey: .microsoft) ?? .init()
    }
}

struct TranscriptChunk: Codable, Identifiable {
    var id: UUID = .init()
    var text: String
    var isFinal: Bool
    var provider: AsrProviderChoice
    var timestamp: Date = .init()
}

struct TranslationChunk: Codable, Identifiable {
    var id: UUID = .init()
    var text: String
    var isFinal: Bool
    var provider: TranslationProviderChoice
    var timestamp: Date = .init()
}
