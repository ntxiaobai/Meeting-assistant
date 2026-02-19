import CMeetingCoreFFI
import Foundation

public struct CoreInvokeError: Error, Decodable {
    public let code: String
    public let message: String
}

private struct InvokeEnvelope<Data: Decodable>: Decodable {
    let ok: Bool
    let data: Data?
    let error: CoreInvokeError?
}

private struct InvokeVoidEnvelope: Decodable {
    let ok: Bool
    let error: CoreInvokeError?
}

private struct InvokeRequest<Payload: Encodable>: Encodable {
    let command: String
    let payload: Payload
}

private struct EmptyPayload: Encodable {}

public struct LiveOverlayLayout: Codable {
    public var opacity: Double
    public var x: Int
    public var y: Int
    public var width: UInt32
    public var height: UInt32
    public var anchorScreen: String?

    public init(
        opacity: Double,
        x: Int,
        y: Int,
        width: UInt32,
        height: UInt32,
        anchorScreen: String?
    ) {
        self.opacity = opacity
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.anchorScreen = anchorScreen
    }
}

public struct WindowModeState: Codable {
    public var alwaysOnTop: Bool
    public var transparent: Bool
    public var undecorated: Bool
    public var clickThrough: Bool
    public var opacity: Double

    public init(
        alwaysOnTop: Bool,
        transparent: Bool,
        undecorated: Bool,
        clickThrough: Bool,
        opacity: Double
    ) {
        self.alwaysOnTop = alwaysOnTop
        self.transparent = transparent
        self.undecorated = undecorated
        self.clickThrough = clickThrough
        self.opacity = opacity
    }
}

public struct WindowAvailability: Codable {
    public var liveOverlay: Bool
}

public struct BootstrapState: Codable {
    public var teleprompter: WindowModeState
    public var liveOverlayLayout: LiveOverlayLayout
    public var windows: WindowAvailability
    public var locale: LocaleCode?
    public var themeMode: ThemeMode?
    public var onboardingCompleted: Bool?
    public var llmSettings: LlmSettings?
}

public enum LocaleCode: String, Codable, CaseIterable, Identifiable {
    case zhCN = "zh-CN"
    case enUS = "en-US"

    public var id: String { rawValue }
}

public enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case light
    case dark
    case system

    public var id: String { rawValue }
}

public enum LlmProviderKind: String, Codable, CaseIterable, Identifiable {
    case anthropic
    case openai
    case custom

    public var id: String { rawValue }
}

public enum LlmApiFormat: String, Codable, CaseIterable, Identifiable {
    case anthropic
    case openai

    public var id: String { rawValue }
}

public struct LlmSettings: Codable {
    public var provider: LlmProviderKind
    public var model: String
    public var baseUrl: String?
    public var apiFormat: LlmApiFormat
}

public struct SaveUserPreferencesInput: Codable {
    public var locale: LocaleCode
    public var themeMode: ThemeMode
    public var onboardingCompleted: Bool

    public init(locale: LocaleCode, themeMode: ThemeMode, onboardingCompleted: Bool) {
        self.locale = locale
        self.themeMode = themeMode
        self.onboardingCompleted = onboardingCompleted
    }
}

public struct SaveLlmSettingsInput: Codable {
    public var provider: LlmProviderKind
    public var model: String
    public var baseUrl: String?
    public var apiFormat: LlmApiFormat

    public init(provider: LlmProviderKind, model: String, baseUrl: String?, apiFormat: LlmApiFormat) {
        self.provider = provider
        self.model = model
        self.baseUrl = baseUrl
        self.apiFormat = apiFormat
    }
}

public enum ProviderKind: String, Codable {
    case aliyun
    case deepgram
    case claude
    case gemini
    case openai
    case customLlm = "custom_llm"
}

public enum ProviderSecretField: String, Codable {
    case apiKey = "api_key"
    case accessKeyId = "access_key_id"
    case accessKeySecret = "access_key_secret"
    case appKey = "app_key"
}

private struct SaveProviderSecretInput: Codable {
    let provider: ProviderKind
    let field: ProviderSecretField
    let value: String
}

public final class CoreClient {
    private var runtimeHandle: UnsafeMutableRawPointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var eventHandler: ((String, String) -> Void)?

    public init(configJSON: String = "{}") throws {
        guard let cConfig = configJSON.cString(using: .utf8) else {
            throw CoreInvokeError(code: "invalid_config", message: "config JSON is not UTF-8")
        }
        runtimeHandle = cConfig.withUnsafeBufferPointer { ptr in
            ma_runtime_new(ptr.baseAddress)
        }
        guard runtimeHandle != nil else {
            throw CoreInvokeError(code: "runtime_init_failed", message: "ma_runtime_new returned nil")
        }

        ma_set_event_callback(runtimeHandle, coreBridgeEventCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        if let runtimeHandle {
            ma_set_event_callback(runtimeHandle, nil, nil)
            ma_runtime_free(runtimeHandle)
            self.runtimeHandle = nil
        }
    }

    public func subscribe(_ handler: @escaping (String, String) -> Void) {
        eventHandler = handler
    }

    public func clearSubscription() {
        eventHandler = nil
    }

    public func invoke<Output: Decodable>(command: String) throws -> Output {
        try invoke(command: command, payload: EmptyPayload())
    }

    public func invoke<Payload: Encodable, Output: Decodable>(
        command: String,
        payload: Payload
    ) throws -> Output {
        let requestJSON = try encodeRequestJSON(command: command, payload: payload)
        guard let raw = invokeRaw(requestJSON: requestJSON) else {
            throw CoreInvokeError(code: "invoke_failed", message: "ma_invoke_json returned nil")
        }

        let rawData = raw.data(using: .utf8) ?? Data()
        let envelope = try decoder.decode(InvokeEnvelope<Output>.self, from: rawData)
        if envelope.ok, let data = envelope.data {
            return data
        }
        throw envelope.error ?? CoreInvokeError(code: "unknown_error", message: "invoke failed")
    }

    public func invokeVoid(command: String) throws {
        try invokeVoid(command: command, payload: EmptyPayload())
    }

    public func invokeVoid<Payload: Encodable>(command: String, payload: Payload) throws {
        let requestJSON = try encodeRequestJSON(command: command, payload: payload)
        guard let raw = invokeRaw(requestJSON: requestJSON) else {
            throw CoreInvokeError(code: "invoke_failed", message: "ma_invoke_json returned nil")
        }
        let rawData = raw.data(using: .utf8) ?? Data()
        let envelope = try decoder.decode(InvokeVoidEnvelope.self, from: rawData)
        if envelope.ok {
            return
        }
        throw envelope.error ?? CoreInvokeError(code: "unknown_error", message: "invoke failed")
    }

    public func getBootstrapState() throws -> BootstrapState {
        try invoke(command: "get_bootstrap_state")
    }

    public func showLiveOverlay() throws -> WindowAvailability {
        try invoke(command: "show_live_overlay")
    }

    public func hideLiveOverlay() throws -> WindowAvailability {
        try invoke(command: "hide_live_overlay")
    }

    public func saveLiveOverlayLayout(_ layout: LiveOverlayLayout) throws -> LiveOverlayLayout {
        try invoke(command: "save_live_overlay_layout", payload: layout)
    }

    public func setLiveOverlayMode(_ mode: WindowModeState) throws -> WindowModeState {
        try invoke(command: "set_live_overlay_mode", payload: mode)
    }

    public func getUserPreferences() throws -> SaveUserPreferencesInput {
        let preferences: UserPreferences = try invoke(command: "get_user_preferences")
        return SaveUserPreferencesInput(
            locale: preferences.locale,
            themeMode: preferences.themeMode,
            onboardingCompleted: preferences.onboardingCompleted
        )
    }

    public func saveUserPreferences(_ input: SaveUserPreferencesInput) throws -> UserPreferences {
        try invoke(command: "save_user_preferences", payload: input)
    }

    public func getLlmSettings() throws -> LlmSettings {
        try invoke(command: "get_llm_settings")
    }

    public func saveLlmSettings(_ input: SaveLlmSettingsInput) throws -> LlmSettings {
        try invoke(command: "save_llm_settings", payload: input)
    }

    public func saveProviderSecret(
        provider: ProviderKind,
        field: ProviderSecretField,
        value: String
    ) throws {
        try invokeVoid(
            command: "save_provider_secret",
            payload: SaveProviderSecretInput(provider: provider, field: field, value: value)
        )
    }

    public func saveProviderKey(provider: ProviderKind, apiKey: String) throws {
        try invokeVoid(
            command: "save_provider_key",
            payload: ["provider": provider.rawValue, "apiKey": apiKey]
        )
    }

    private func encodeRequestJSON<Payload: Encodable>(
        command: String,
        payload: Payload
    ) throws -> String {
        let request = InvokeRequest(command: command, payload: payload)
        let requestData = try encoder.encode(request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw CoreInvokeError(
                code: "request_encoding_failed",
                message: "failed to encode invoke request"
            )
        }
        return requestJSON
    }

    private func invokeRaw(requestJSON: String) -> String? {
        guard let runtimeHandle, let cRequest = requestJSON.cString(using: .utf8) else {
            return nil
        }
        let rawPtr = cRequest.withUnsafeBufferPointer { ptr in
            ma_invoke_json(runtimeHandle, ptr.baseAddress)
        }
        guard let rawPtr else {
            return nil
        }
        defer {
            ma_free_c_string(rawPtr)
        }
        return String(cString: rawPtr)
    }

    fileprivate func dispatchEventJSON(_ json: String) {
        let data = json.data(using: .utf8) ?? Data()
        if
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = object["event"] as? String
        {
            eventHandler?(event, json)
        } else {
            eventHandler?("runtime://unknown", json)
        }
    }
}

public struct UserPreferences: Codable {
    public var locale: LocaleCode
    public var themeMode: ThemeMode
    public var onboardingCompleted: Bool
    public var llmSettings: LlmSettings?
    public var teleprompterMode: WindowModeState?
    public var liveOverlayLayout: LiveOverlayLayout?
}

private func coreBridgeEventCallback(
    eventJSON: UnsafePointer<CChar>?,
    userData: UnsafeMutableRawPointer?
) -> Void {
    guard
        let eventJSON,
        let userData
    else {
        return
    }
    let client = Unmanaged<CoreClient>.fromOpaque(userData).takeUnretainedValue()
    let json = String(cString: eventJSON)
    DispatchQueue.main.async {
        client.dispatchEventJSON(json)
    }
}
