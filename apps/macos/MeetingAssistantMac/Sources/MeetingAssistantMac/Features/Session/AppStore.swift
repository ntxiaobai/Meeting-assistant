import AppKit
import CoreBridge
import Foundation

@MainActor
final class AppStore: ObservableObject {
    enum StatusTone {
        case info
        case success
        case warning
        case error
    }

    @Published var statusText: String = "Initializing Core Runtime..."
    @Published var statusTone: StatusTone = .info
    @Published var isStubRuntime: Bool = false

    @Published var locale: LocaleCode = .enUS
    @Published var themeMode: ThemeMode = .system

    @Published var llmProvider: LlmProviderKind = .anthropic
    @Published var llmModel: String = "claude-3-5-sonnet-latest"
    @Published var llmBaseURL: String = ""
    @Published var llmApiFormat: LlmApiFormat = .anthropic
    @Published var llmApiKeyDraft: String = ""

    @Published var speechPipelineSettings = SpeechPipelineSettings()
    @Published var deepgramConfig = DeepgramConfig()
    @Published var aliyunConfig = AliyunConfig()
    @Published var microsoftConfig = MicrosoftTranslatorConfig()

    @Published var deepgramApiKeyDraft: String = ""
    @Published var aliyunAccessKeyIdDraft: String = ""
    @Published var aliyunAccessKeySecretDraft: String = ""
    @Published var aliyunAppKeyDraft: String = ""
    @Published var microsoftTranslatorApiKeyDraft: String = ""
    @Published var deepgramSecretConfigured: Bool = false
    @Published var aliyunSecretConfigured: Bool = false
    @Published var microsoftSecretConfigured: Bool = false
    @Published var secretProfiles: [ProviderSecretProfileSummary] = []
    @Published var activeSecretProfileId: String = ""
    @Published var secretProfileNameDraft: String = ""

    @Published var runtimeStatus = RuntimeStatus()
    @Published var runtimeLogs: [String] = []
    @Published var liveTranscripts: [TranscriptChunk] = []
    @Published var liveTranslations: [TranslationChunk] = []
    @Published var latestAnswerHint: String = ""
    @Published var answerHintsEnabled: Bool = true
    @Published var speechSegmentCount: Int = 0
    @Published var translationSegmentCount: Int = 0
    @Published var speechTokenEstimate: Int = 0
    @Published var translationTokenEstimate: Int = 0
    @Published var hintRequestCount: Int = 0
    @Published var hintInputTokenEstimate: Int = 0
    @Published var hintOutputTokenEstimate: Int = 0

    @Published var speechApiTestMessage: String = "未测试"
    @Published var speechApiTestTone: StatusTone = .info
    @Published var speechApiTesting: Bool = false
    @Published var translationApiTestMessage: String = "未测试"
    @Published var translationApiTestTone: StatusTone = .info
    @Published var translationApiTestTesting: Bool = false
    @Published var hintsApiTestMessage: String = "未测试"
    @Published var hintsApiTestTone: StatusTone = .info
    @Published var hintsApiTestTesting: Bool = false

    @Published var overlayOpacity: Double = 0.86
    @Published var overlayAlwaysOnTop: Bool = true
    @Published var overlayVisible: Bool = false
    @Published var overlayPositionText: String = "-"

    let overlayController = OverlayWindowController()

    private let providerConfigStore = ProviderConfigStore()
    private let keychainStore = KeychainSecretStore()
    private let sessionEngine = SessionEngine()
    private var coreClient: CoreClient?
    private var secretSnapshotCache: ProviderSecretSnapshot?
    private var secretSnapshotProfileId: String?
    private let answerHintsEnabledDefaultsKey = "meeting_assistant.mac.answer_hints_enabled.v1"
    private let llmDraftDefaultsKey = "meeting_assistant.mac.llm_draft.v1"

    init() {
        loadSpeechSettingsFromDisk()
        reloadSecretProfilesFromStore(forceReload: true)
        restoreSecretsFromActiveProfile(forceReload: true)
        restoreLlmDraftFromDefaults()
        loadAnswerHintsPreference()
        bindSessionCallbacks()

        do {
            let client = try CoreClient()
            self.coreClient = client
            overlayController.onLayoutChanged = { [weak self] layout in
                self?.syncOverlayLayoutToCore(layout)
            }
            overlayController.onCloseRequested = { [weak self] in
                self?.closeOverlay()
            }
            overlayController.onToggleHintsRequested = { [weak self] enabled in
                self?.setAnswerHintsEnabled(enabled)
            }
            client.subscribe { [weak self] event, _ in
                self?.setStatus("Event: \(event)", tone: .info)
            }
            refreshBootstrap()
            setStatus("Core runtime is ready.", tone: .success)
        } catch {
            setStatus("Core runtime init failed: \(error)", tone: .error)
        }
    }

    func refreshBootstrap() {
        if isStubRuntime { return }
        guard let coreClient else { return }

        do {
            let bootstrap = try coreClient.getBootstrapState()
            locale = bootstrap.locale ?? locale
            themeMode = bootstrap.themeMode ?? themeMode
            if let llm = bootstrap.llmSettings {
                llmProvider = llm.provider
                llmModel = llm.model
                llmBaseURL = llm.baseUrl ?? ""
                llmApiFormat = llm.apiFormat
                llmApiKeyDraft = llmApiKey(for: llmProvider, from: loadSecretsForSession()) ?? ""
            }

            overlayOpacity = bootstrap.liveOverlayLayout.opacity
            overlayAlwaysOnTop = bootstrap.teleprompter.alwaysOnTop
            overlayVisible = bootstrap.windows.liveOverlay
            overlayController.configure(initialLayout: bootstrap.liveOverlayLayout)
            overlayController.setAlwaysOnTop(bootstrap.teleprompter.alwaysOnTop)
            overlayPositionText = layoutText(bootstrap.liveOverlayLayout)
            if bootstrap.onboardingCompleted == false {
                applyUserPreferences()
            }
            setStatus("Bootstrap loaded.", tone: .success)
        } catch {
            handleCoreError(operation: "get_bootstrap_state", error: error)
        }
    }

    func applyOverlayOpacity() {
        overlayController.setOpacity(overlayOpacity)
        persistOverlayMode()
    }

    func applyAlwaysOnTop() {
        overlayController.setAlwaysOnTop(overlayAlwaysOnTop)
        persistOverlayMode()
    }

    func openOverlay() {
        if isStubRuntime {
            overlayVisible = true
            overlayController.show()
            setStatus("Preview mode: local overlay shown.", tone: .warning)
            return
        }

        do {
            let availability = try coreClient?.showLiveOverlay()
            overlayVisible = availability?.liveOverlay ?? true
        } catch {
            handleCoreError(operation: "show_live_overlay", error: error)
        }

        overlayController.show()
    }

    func closeOverlay() {
        if isStubRuntime {
            overlayVisible = false
            overlayController.hide()
            return
        }

        do {
            let availability = try coreClient?.hideLiveOverlay()
            overlayVisible = availability?.liveOverlay ?? false
        } catch {
            handleCoreError(operation: "hide_live_overlay", error: error)
        }

        overlayController.hide()
    }

    func resetOverlayLayout() {
        let layout = overlayController.resetToDefaultLayout()
        syncOverlayLayoutToCore(layout)
    }

    func applyUserPreferences() {
        if isStubRuntime {
            return
        }
        guard let coreClient else { return }

        do {
            let saved = try coreClient.saveUserPreferences(
                SaveUserPreferencesInput(
                    locale: locale,
                    themeMode: themeMode,
                    onboardingCompleted: true
                )
            )
            locale = saved.locale
            themeMode = saved.themeMode
        } catch {
            handleCoreError(operation: "save_user_preferences", error: error)
        }
    }

    func saveLlmSettings() {
        let model = llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty {
            setStatus("Model cannot be empty.", tone: .warning)
            return
        }
        if llmProvider == .custom,
           llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            setStatus("Custom provider requires Base URL.", tone: .warning)
            return
        }
        if isStubRuntime {
            setStatus("Preview mode: LLM settings are not persisted to Rust core.", tone: .warning)
            return
        }

        guard let coreClient else { return }

        do {
            let saved = try coreClient.saveLlmSettings(
                SaveLlmSettingsInput(
                    provider: llmProvider,
                    model: model,
                    baseUrl: llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil
                        : llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    apiFormat: llmApiFormat
                )
            )
            llmProvider = saved.provider
            llmModel = saved.model
            llmBaseURL = saved.baseUrl ?? ""
            llmApiFormat = saved.apiFormat
            saveLlmDraftToDefaults()
            setStatus("LLM settings saved.", tone: .success)
        } catch {
            handleCoreError(operation: "save_llm_settings", error: error)
        }
    }

    func saveLlmApiKey() {
        let apiKey = llmApiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if apiKey.isEmpty {
            setStatus("API key cannot be empty.", tone: .warning)
            return
        }
        if isStubRuntime {
            setStatus("Preview mode: API key is not persisted to Keychain.", tone: .warning)
            return
        }

        guard let coreClient else { return }

        do {
            try coreClient.saveProviderSecret(
                provider: providerKindForLlm(llmProvider),
                field: .apiKey,
                value: apiKey
            )
            saveLlmApiKeyToLocalProfile(apiKey)
            llmApiKeyDraft = apiKey
            setStatus("Provider key saved to Keychain.", tone: .success)
        } catch {
            handleCoreError(operation: "save_provider_secret", error: error)
        }
    }

    func saveSpeechProviderSettings() {
        persistSpeechProviderSettings(showStatus: true)
    }

    func saveDeepgramSecret() {
        let key = deepgramApiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            setStatus("Deepgram API key cannot be empty.", tone: .warning)
            return
        }

        if keychainStore.saveDeepgramApiKey(key) {
            deepgramApiKeyDraft = key
            var snapshot = secretSnapshotCache ?? ProviderSecretSnapshot()
            snapshot.deepgramApiKey = key
            secretSnapshotCache = snapshot
            secretSnapshotProfileId = keychainStore.activeProfileId()
            refreshSecretStatus(snapshot)
            setStatus("Deepgram key saved (\(activeSecretProfileName())).", tone: .success)
            reloadSecretProfilesFromStore(forceReload: true)
        } else {
            setStatus("Failed to save Deepgram key.", tone: .error)
        }
    }

    func saveAliyunSecrets() {
        let accessKeyId = aliyunAccessKeyIdDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let accessKeySecret = aliyunAccessKeySecretDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let appKey = aliyunAppKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !accessKeyId.isEmpty, !accessKeySecret.isEmpty, !appKey.isEmpty else {
            setStatus("Aliyun credentials are incomplete.", tone: .warning)
            return
        }

        if keychainStore.saveAliyun(
            accessKeyId: accessKeyId,
            accessKeySecret: accessKeySecret,
            appKey: appKey
        ) {
            aliyunAccessKeyIdDraft = accessKeyId
            aliyunAccessKeySecretDraft = accessKeySecret
            aliyunAppKeyDraft = appKey
            var snapshot = secretSnapshotCache ?? ProviderSecretSnapshot()
            snapshot.aliyunAccessKeyId = accessKeyId
            snapshot.aliyunAccessKeySecret = accessKeySecret
            snapshot.aliyunAppKey = appKey
            secretSnapshotCache = snapshot
            secretSnapshotProfileId = keychainStore.activeProfileId()
            refreshSecretStatus(snapshot)
            setStatus("Aliyun credentials saved (\(activeSecretProfileName())).", tone: .success)
            reloadSecretProfilesFromStore(forceReload: true)
        } else {
            setStatus("Failed to save Aliyun credentials.", tone: .error)
        }
    }

    func saveMicrosoftTranslatorSecret() {
        let key = microsoftTranslatorApiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            setStatus("Microsoft Translator API key cannot be empty.", tone: .warning)
            return
        }

        if keychainStore.saveMicrosoftTranslatorKey(key) {
            microsoftTranslatorApiKeyDraft = key
            var snapshot = secretSnapshotCache ?? ProviderSecretSnapshot()
            snapshot.microsoftTranslatorKey = key
            secretSnapshotCache = snapshot
            secretSnapshotProfileId = keychainStore.activeProfileId()
            refreshSecretStatus(snapshot)
            setStatus("Microsoft Translator key saved (\(activeSecretProfileName())).", tone: .success)
            reloadSecretProfilesFromStore(forceReload: true)
        } else {
            setStatus("Failed to save Microsoft Translator key.", tone: .error)
        }
    }

    func selectSecretProfile(_ profileId: String) {
        guard !profileId.isEmpty else { return }
        guard profileId != keychainStore.activeProfileId() else { return }

        if keychainStore.setActiveProfile(profileId) {
            reloadSecretProfilesFromStore(forceReload: true)
            restoreSecretsFromActiveProfile(forceReload: true)
            setStatus("Switched key profile to \(activeSecretProfileName()).", tone: .success)
        } else {
            setStatus("Failed to switch key profile.", tone: .error)
        }
    }

    func createSecretProfile() {
        let name = secretProfileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            setStatus("Profile name cannot be empty.", tone: .warning)
            return
        }

        guard keychainStore.createProfile(name: name) != nil else {
            setStatus("Failed to create key profile.", tone: .error)
            return
        }

        secretProfileNameDraft = ""
        reloadSecretProfilesFromStore(forceReload: true)
        restoreSecretsFromActiveProfile(forceReload: true)
        setStatus("Created and switched to key profile \(activeSecretProfileName()).", tone: .success)
    }

    func setAnswerHintsEnabled(_ enabled: Bool) {
        if answerHintsEnabled == enabled {
            overlayController.setHintsEnabled(enabled)
            return
        }

        answerHintsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: answerHintsEnabledDefaultsKey)
        overlayController.setHintsEnabled(enabled)
        if !enabled {
            latestAnswerHint = ""
            overlayController.updateHint("")
        }
    }

    func setTranslationEnabled(_ enabled: Bool) {
        if speechPipelineSettings.translationEnabled == enabled {
            return
        }
        speechPipelineSettings.translationEnabled = enabled
        saveSpeechProviderSettings()

        if !enabled {
            liveTranslations.removeAll(keepingCapacity: true)
            translationSegmentCount = 0
            translationTokenEstimate = 0
            overlayController.updateTranslation(emptyTranslationChunk())
        }
    }

    func startSession() {
        liveTranscripts.removeAll(keepingCapacity: true)
        liveTranslations.removeAll(keepingCapacity: true)
        latestAnswerHint = ""
        speechSegmentCount = 0
        translationSegmentCount = 0
        speechTokenEstimate = 0
        translationTokenEstimate = 0
        hintRequestCount = 0
        hintInputTokenEstimate = 0
        hintOutputTokenEstimate = 0
        overlayController.clearContent()
        overlayController.setHintsEnabled(answerHintsEnabled)

        let snapshot = loadSecretsForSession()
        let input = SessionEngine.StartInput(
            settings: speechPipelineSettings,
            deepgram: deepgramConfig,
            aliyun: aliyunConfig,
            microsoft: microsoftConfig,
            secrets: snapshot
        )

        Task {
            await sessionEngine.start(input)
        }
    }

    func stopSession() {
        Task {
            await sessionEngine.stop()
        }
    }

    func copyRuntimeLogs() {
        let value = runtimeLogs.joined(separator: "\n")
        guard !value.isEmpty else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        setStatus("Runtime logs copied to clipboard.", tone: .success)
    }

    func reloadSecretStatusFromKeychain() {
        reloadSecretProfilesFromStore(forceReload: true)
        restoreSecretsFromActiveProfile(forceReload: true)
        setStatus("Secret status refreshed (\(activeSecretProfileName())).", tone: .info)
    }

    func restoreLlmApiKeyDraftForCurrentProvider() {
        let snapshot = loadSecretsForSession()
        llmApiKeyDraft = llmApiKey(for: llmProvider, from: snapshot) ?? ""
    }

    func saveSpeechProviderSettingsSilently() {
        persistSpeechProviderSettings(showStatus: false)
    }

    func saveLlmSettingsDraftSilently() {
        saveLlmDraftToDefaults()
    }

    func testSpeechApiConnection() {
        if speechApiTesting {
            return
        }
        speechApiTesting = true
        speechApiTestTone = .info
        speechApiTestMessage = "测试中..."

        Task {
            do {
                let message = try await runSpeechApiConnectionTest()
                speechApiTestTone = .success
                speechApiTestMessage = message
                setStatus("Speech API test passed: \(message)", tone: .success)
            } catch {
                speechApiTestTone = .error
                speechApiTestMessage = error.localizedDescription
                setStatus("Speech API test failed: \(error.localizedDescription)", tone: .error)
            }
            speechApiTesting = false
        }
    }

    func testTranslationApiConnection() {
        if translationApiTestTesting {
            return
        }
        translationApiTestTesting = true
        translationApiTestTone = .info
        translationApiTestMessage = "测试中..."

        Task {
            do {
                let message = try await runTranslationApiConnectionTest()
                translationApiTestTone = .success
                translationApiTestMessage = message
                setStatus("Translation API test passed: \(message)", tone: .success)
            } catch {
                translationApiTestTone = .error
                translationApiTestMessage = error.localizedDescription
                setStatus("Translation API test failed: \(error.localizedDescription)", tone: .error)
            }
            translationApiTestTesting = false
        }
    }

    func testHintsApiConnection() {
        if hintsApiTestTesting {
            return
        }
        hintsApiTestTesting = true
        hintsApiTestTone = .info
        hintsApiTestMessage = "测试中..."

        Task {
            do {
                let message = try await runHintsApiConnectionTest()
                hintsApiTestTone = .success
                hintsApiTestMessage = message
                setStatus("Hint model API test passed: \(message)", tone: .success)
            } catch {
                hintsApiTestTone = .error
                hintsApiTestMessage = error.localizedDescription
                setStatus("Hint model API test failed: \(error.localizedDescription)", tone: .error)
            }
            hintsApiTestTesting = false
        }
    }

    func quickSwitchAudioSource(_ mode: AudioSourceMode) {
        speechPipelineSettings.audioSourceMode = mode
        saveSpeechProviderSettings()
    }

    func quickSwitchAsrProvider(_ provider: AsrProviderChoice) {
        speechPipelineSettings.asrProvider = provider
        saveSpeechProviderSettings()
    }

    func activateMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    var sessionRunning: Bool {
        runtimeStatus.sessionState == .running || runtimeStatus.sessionState == .starting
    }

    var statusLabel: String {
        switch statusTone {
        case .info:
            return "Info"
        case .success:
            return "Ready"
        case .warning:
            return "Warning"
        case .error:
            return "Error"
        }
    }

    var statusSymbol: String {
        switch statusTone {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }
}

private extension AppStore {
    struct LlmDraftSnapshot: Codable {
        var provider: LlmProviderKind
        var model: String
        var baseURL: String
        var apiFormat: LlmApiFormat
    }

    func loadAnswerHintsPreference() {
        if UserDefaults.standard.object(forKey: answerHintsEnabledDefaultsKey) != nil {
            answerHintsEnabled = UserDefaults.standard.bool(forKey: answerHintsEnabledDefaultsKey)
        } else {
            answerHintsEnabled = true
        }
        overlayController.setHintsEnabled(answerHintsEnabled)
    }

    func restoreLlmDraftFromDefaults() {
        guard let raw = UserDefaults.standard.data(forKey: llmDraftDefaultsKey),
              let draft = try? JSONDecoder().decode(LlmDraftSnapshot.self, from: raw)
        else {
            return
        }

        llmProvider = draft.provider
        llmModel = draft.model
        llmBaseURL = draft.baseURL
        llmApiFormat = draft.apiFormat
        llmApiKeyDraft = llmApiKey(for: llmProvider, from: loadSecretsForSession()) ?? ""
    }

    func saveLlmDraftToDefaults() {
        let draft = LlmDraftSnapshot(
            provider: llmProvider,
            model: llmModel,
            baseURL: llmBaseURL,
            apiFormat: llmApiFormat
        )
        guard let raw = try? JSONEncoder().encode(draft) else {
            return
        }
        UserDefaults.standard.set(raw, forKey: llmDraftDefaultsKey)
    }

    func refreshSecretStatus(_ snapshot: ProviderSecretSnapshot) {
        deepgramSecretConfigured = !(snapshot.deepgramApiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasAccessKeyId = !(snapshot.aliyunAccessKeyId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasAccessKeySecret = !(snapshot.aliyunAccessKeySecret?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasAppKey = !(snapshot.aliyunAppKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        aliyunSecretConfigured = hasAccessKeyId && hasAccessKeySecret && hasAppKey
        microsoftSecretConfigured = !(snapshot.microsoftTranslatorKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func reloadSecretProfilesFromStore(forceReload: Bool = false) {
        let profiles = keychainStore.listProfiles(forceReload: forceReload)
        secretProfiles = profiles
        let activeId = keychainStore.activeProfileId(forceReload: forceReload) ?? profiles.first?.id ?? ""
        if activeSecretProfileId != activeId {
            activeSecretProfileId = activeId
        }
    }

    func activeSecretProfileName() -> String {
        keychainStore.activeProfileName() ?? "Unnamed Profile"
    }

    func loadSecretsForSession() -> ProviderSecretSnapshot {
        let activeProfileId = keychainStore.activeProfileId()
        if let secretSnapshotCache,
           activeProfileId == secretSnapshotProfileId
        {
            return secretSnapshotCache
        }
        let snapshot = keychainStore.loadSnapshot()
        secretSnapshotCache = snapshot
        secretSnapshotProfileId = activeProfileId
        refreshSecretStatus(snapshot)
        reloadSecretProfilesFromStore()
        return snapshot
    }

    func loadSpeechSettingsFromDisk() {
        let settings = providerConfigStore.load()
        speechPipelineSettings = settings.pipeline
        deepgramConfig = settings.deepgram
        aliyunConfig = settings.aliyun
        microsoftConfig = settings.microsoft
    }

    func persistSpeechProviderSettings(showStatus: Bool) {
        let next = SpeechSettingsEnvelope(
            pipeline: speechPipelineSettings,
            deepgram: deepgramConfig,
            aliyun: aliyunConfig,
            microsoft: microsoftConfig
        )

        do {
            try providerConfigStore.save(next)
            if showStatus {
                setStatus("Speech provider settings saved.", tone: .success)
            }
        } catch {
            setStatus("Failed to save speech settings: \(error.localizedDescription)", tone: .error)
        }
    }

    func restoreSecretsFromActiveProfile(forceReload: Bool) {
        let snapshot = keychainStore.loadSnapshot(forceReload: forceReload)
        secretSnapshotCache = snapshot
        secretSnapshotProfileId = keychainStore.activeProfileId(forceReload: forceReload)
        refreshSecretStatus(snapshot)
        restoreDrafts(from: snapshot)
    }

    func restoreDrafts(from snapshot: ProviderSecretSnapshot) {
        deepgramApiKeyDraft = snapshot.deepgramApiKey ?? ""
        aliyunAccessKeyIdDraft = snapshot.aliyunAccessKeyId ?? ""
        aliyunAccessKeySecretDraft = snapshot.aliyunAccessKeySecret ?? ""
        aliyunAppKeyDraft = snapshot.aliyunAppKey ?? ""
        microsoftTranslatorApiKeyDraft = snapshot.microsoftTranslatorKey ?? ""
        llmApiKeyDraft = llmApiKey(for: llmProvider, from: snapshot) ?? ""
    }

    func saveLlmApiKeyToLocalProfile(_ apiKey: String) {
        var snapshot = loadSecretsForSession()
        switch llmProvider {
        case .anthropic:
            snapshot.anthropicApiKey = apiKey
        case .openai:
            snapshot.openaiApiKey = apiKey
        case .custom:
            snapshot.customLlmApiKey = apiKey
        }

        if keychainStore.saveSnapshot(snapshot) {
            secretSnapshotCache = snapshot
            secretSnapshotProfileId = keychainStore.activeProfileId()
            reloadSecretProfilesFromStore(forceReload: true)
        }
    }

    func llmApiKey(for provider: LlmProviderKind, from snapshot: ProviderSecretSnapshot) -> String? {
        switch provider {
        case .anthropic:
            return snapshot.anthropicApiKey
        case .openai:
            return snapshot.openaiApiKey
        case .custom:
            return snapshot.customLlmApiKey
        }
    }

    func resolvedCredential(draft: String, fallback: String?) -> String {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDraft.isEmpty {
            return trimmedDraft
        }
        return fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func runSpeechApiConnectionTest() async throws -> String {
        let snapshot = loadSecretsForSession()
        switch speechPipelineSettings.asrProvider {
        case .deepgram:
            let apiKey = resolvedCredential(draft: deepgramApiKeyDraft, fallback: snapshot.deepgramApiKey)
            guard !apiKey.isEmpty else {
                throw NSError(domain: "AppStore", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Deepgram API key is empty."])
            }
            try await verifyDeepgramApiKey(apiKey)
            return "Deepgram 连接成功。"

        case .aliyun:
            let accessKeyId = resolvedCredential(draft: aliyunAccessKeyIdDraft, fallback: snapshot.aliyunAccessKeyId)
            let accessKeySecret = resolvedCredential(draft: aliyunAccessKeySecretDraft, fallback: snapshot.aliyunAccessKeySecret)
            let appKey = resolvedCredential(draft: aliyunAppKeyDraft, fallback: snapshot.aliyunAppKey)
            guard !accessKeyId.isEmpty, !accessKeySecret.isEmpty, !appKey.isEmpty else {
                throw NSError(domain: "AppStore", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Aliyun credentials are incomplete."])
            }
            try await verifyAliyunConnection(
                accessKeyId: accessKeyId,
                accessKeySecret: accessKeySecret,
                appKey: appKey
            )
            return "阿里云语音链路连接成功。"
        }
    }

    func runTranslationApiConnectionTest() async throws -> String {
        let snapshot = loadSecretsForSession()
        switch speechPipelineSettings.translationProvider {
        case .microsoft:
            let apiKey = resolvedCredential(
                draft: microsoftTranslatorApiKeyDraft,
                fallback: snapshot.microsoftTranslatorKey
            )
            guard !apiKey.isEmpty else {
                throw NSError(domain: "AppStore", code: 1101, userInfo: [NSLocalizedDescriptionKey: "Microsoft Translator API key is empty."])
            }

            let translator = MicrosoftTranslatorClient(
                apiKey: apiKey,
                endpoint: microsoftConfig.endpoint,
                region: microsoftConfig.region
            )
            let translated = try await translator.translate(
                text: "Connection test",
                from: aliyunConfig.sourceLanguage,
                to: aliyunConfig.targetLanguage
            )
            let output = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else {
                throw NSError(domain: "AppStore", code: 1102, userInfo: [NSLocalizedDescriptionKey: "Microsoft Translator returned empty response."])
            }
            return "Microsoft Translator 连接成功。"

        case .aliyun:
            let accessKeyId = resolvedCredential(draft: aliyunAccessKeyIdDraft, fallback: snapshot.aliyunAccessKeyId)
            let accessKeySecret = resolvedCredential(draft: aliyunAccessKeySecretDraft, fallback: snapshot.aliyunAccessKeySecret)
            let appKey = resolvedCredential(draft: aliyunAppKeyDraft, fallback: snapshot.aliyunAppKey)
            guard !accessKeyId.isEmpty, !accessKeySecret.isEmpty, !appKey.isEmpty else {
                throw NSError(domain: "AppStore", code: 1103, userInfo: [NSLocalizedDescriptionKey: "Aliyun credentials are incomplete."])
            }
            try await verifyAliyunConnection(
                accessKeyId: accessKeyId,
                accessKeySecret: accessKeySecret,
                appKey: appKey
            )
            return "阿里云翻译链路连接成功。"
        }
    }

    func runHintsApiConnectionTest() async throws -> String {
        let snapshot = loadSecretsForSession()
        let apiKey = resolvedCredential(draft: llmApiKeyDraft, fallback: llmApiKey(for: llmProvider, from: snapshot))
        guard !apiKey.isEmpty else {
            throw NSError(domain: "AppStore", code: 1201, userInfo: [NSLocalizedDescriptionKey: "Hint model API key is empty."])
        }

        switch llmProvider {
        case .anthropic:
            try await verifyAnthropicConnection(
                apiKey: apiKey,
                baseURL: "https://api.anthropic.com/v1"
            )
            return "Anthropic 连接成功。"
        case .openai:
            let baseURL = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "https://api.openai.com/v1"
                : llmBaseURL
            try await verifyOpenAICompatibleConnection(apiKey: apiKey, baseURL: baseURL)
            return "OpenAI 连接成功。"
        case .custom:
            let baseURL = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !baseURL.isEmpty else {
                throw NSError(domain: "AppStore", code: 1202, userInfo: [NSLocalizedDescriptionKey: "Custom provider requires Base URL."])
            }
            switch llmApiFormat {
            case .openai:
                try await verifyOpenAICompatibleConnection(apiKey: apiKey, baseURL: baseURL)
                return "Custom(OpenAI) 连接成功。"
            case .anthropic:
                try await verifyAnthropicConnection(apiKey: apiKey, baseURL: baseURL)
                return "Custom(Anthropic) 连接成功。"
            }
        }
    }

    func verifyDeepgramApiKey(_ apiKey: String) async throws {
        guard let url = URL(string: "https://api.deepgram.com/v1/projects") else {
            throw NSError(domain: "AppStore", code: 1301, userInfo: [NSLocalizedDescriptionKey: "Invalid Deepgram endpoint URL."])
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.httpMethod = "GET"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw NSError(
                domain: "AppStore",
                code: 1302,
                userInfo: [NSLocalizedDescriptionKey: "Deepgram test failed: status=\(statusCode), body=\(body.prefix(240))"]
            )
        }
    }

    func verifyAliyunConnection(
        accessKeyId: String,
        accessKeySecret: String,
        appKey: String
    ) async throws {
        let client = AliyunRealtimeClient(
            accessKeyId: accessKeyId,
            accessKeySecret: accessKeySecret,
            appKey: appKey,
            sourceLanguage: aliyunConfig.sourceLanguage,
            targetLanguage: aliyunConfig.targetLanguage,
            captureTranscript: false
        )
        do {
            try await withTimeout(seconds: 15) {
                try await client.start()
            }
        } catch {
            await client.stop()
            throw error
        }
        await client.stop()
    }

    func verifyOpenAICompatibleConnection(apiKey: String, baseURL: String) async throws {
        let normalizedBase = normalizedBaseURL(baseURL)
        guard let url = URL(string: "\(normalizedBase)/models") else {
            throw NSError(domain: "AppStore", code: 1401, userInfo: [NSLocalizedDescriptionKey: "OpenAI-compatible Base URL is invalid."])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw NSError(
                domain: "AppStore",
                code: 1402,
                userInfo: [NSLocalizedDescriptionKey: "OpenAI-compatible test failed: status=\(statusCode), body=\(body.prefix(240))"]
            )
        }
    }

    func verifyAnthropicConnection(apiKey: String, baseURL: String) async throws {
        let normalizedBase = normalizedBaseURL(baseURL)
        guard let url = URL(string: "\(normalizedBase)/models") else {
            throw NSError(domain: "AppStore", code: 1501, userInfo: [NSLocalizedDescriptionKey: "Anthropic Base URL is invalid."])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw NSError(
                domain: "AppStore",
                code: 1502,
                userInfo: [NSLocalizedDescriptionKey: "Anthropic test failed: status=\(statusCode), body=\(body.prefix(240))"]
            )
        }
    }

    func normalizedBaseURL(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let timeoutNanoseconds = UInt64(seconds * 1_000_000_000)
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw NSError(
                    domain: "AppStore",
                    code: 1601,
                    userInfo: [NSLocalizedDescriptionKey: "Request timed out after \(Int(seconds))s."]
                )
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    func bindSessionCallbacks() {
        sessionEngine.onStatus = { [weak self] status in
            self?.runtimeStatus = status
            self?.appendRuntimeLog(
                "status=\(status.sessionState.rawValue) permission=\(status.permissionState.rawValue) providers=\(status.activeProviders.joined(separator: ",")) warning=\(status.warningCode ?? "-")"
            )
            if status.sessionState == .running {
                self?.statusTone = .success
            }
        }

        sessionEngine.onMessage = { [weak self] message in
            let lowercased = message.lowercased()
            if lowercased.contains("failed") || lowercased.contains("error") {
                self?.setStatus(message, tone: .error)
            } else if self?.runtimeStatus.sessionState == .running {
                self?.setStatus(message, tone: .success)
            } else {
                self?.setStatus(message, tone: .info)
            }
        }

        sessionEngine.onTranscript = { [weak self] chunk in
            self?.appendTranscriptChunk(chunk)
            if chunk.isFinal {
                self?.speechSegmentCount += 1
                self?.speechTokenEstimate += self?.estimateTokens(chunk.text) ?? 0
            }
            self?.updateAnswerHintIfNeeded(using: chunk)
        }

        sessionEngine.onTranslation = { [weak self] chunk in
            guard self?.speechPipelineSettings.translationEnabled == true else {
                return
            }
            self?.appendTranslationChunk(chunk)
            if chunk.isFinal {
                self?.translationSegmentCount += 1
                self?.translationTokenEstimate += self?.estimateTokens(chunk.text) ?? 0
            }
        }
    }

    func appendTranscriptChunk(_ chunk: TranscriptChunk) {
        let text = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if liveTranscripts.isEmpty {
            var next = chunk
            next.text = text
            liveTranscripts.append(next)
            refreshOverlayTranscript(using: next)
            return
        }

        if chunk.isFinal {
            if let lastIndex = liveTranscripts.indices.last, !liveTranscripts[lastIndex].isFinal {
                liveTranscripts[lastIndex].text = text
                liveTranscripts[lastIndex].isFinal = true
                liveTranscripts[lastIndex].provider = chunk.provider
                liveTranscripts[lastIndex].timestamp = chunk.timestamp
                mergeTranscriptIfNeeded(at: lastIndex)
            } else {
                var next = chunk
                next.text = text
                liveTranscripts.append(next)
                mergeTranscriptIfNeeded(at: liveTranscripts.count - 1)
            }
        } else if let lastIndex = liveTranscripts.indices.last, !liveTranscripts[lastIndex].isFinal {
            liveTranscripts[lastIndex].text = text
            liveTranscripts[lastIndex].timestamp = chunk.timestamp
            liveTranscripts[lastIndex].provider = chunk.provider
        } else {
            var next = chunk
            next.text = text
            next.isFinal = false
            liveTranscripts.append(next)
        }

        if liveTranscripts.count > 400 {
            liveTranscripts.removeFirst(liveTranscripts.count - 300)
        }
        refreshOverlayTranscript(using: chunk)
    }

    func appendTranslationChunk(_ chunk: TranslationChunk) {
        let text = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let incomingKey = normalizedRealtimeLine(text)
        guard !incomingKey.isEmpty else { return }

        if liveTranslations.isEmpty {
            var next = chunk
            next.text = text
            liveTranslations.append(next)
            refreshOverlayTranslation(using: next)
            return
        }

        if let lastIndex = liveTranslations.indices.last {
            let lastKey = normalizedRealtimeLine(liveTranslations[lastIndex].text)
            if incomingKey == lastKey {
                liveTranslations[lastIndex].text = text
                liveTranslations[lastIndex].timestamp = chunk.timestamp
                liveTranslations[lastIndex].provider = chunk.provider
                if chunk.isFinal {
                    liveTranslations[lastIndex].isFinal = true
                }
                refreshOverlayTranslation(using: liveTranslations[lastIndex])
                return
            }
        }

        if chunk.isFinal,
           let duplicateFinalIndex = recentDuplicateFinalTranslationIndex(
               normalizedText: incomingKey,
               now: chunk.timestamp
           ),
           duplicateFinalIndex == liveTranslations.count - 1
        {
            liveTranslations[duplicateFinalIndex].timestamp = chunk.timestamp
            liveTranslations[duplicateFinalIndex].provider = chunk.provider
            refreshOverlayTranslation(using: liveTranslations[duplicateFinalIndex])
            return
        }

        if chunk.isFinal {
            if let lastIndex = liveTranslations.indices.last, !liveTranslations[lastIndex].isFinal {
                liveTranslations[lastIndex].text = text
                liveTranslations[lastIndex].isFinal = true
                liveTranslations[lastIndex].provider = chunk.provider
                liveTranslations[lastIndex].timestamp = chunk.timestamp
                mergeTranslationIfNeeded(at: lastIndex)
            } else {
                var next = chunk
                next.text = text
                liveTranslations.append(next)
                mergeTranslationIfNeeded(at: liveTranslations.count - 1)
            }
        } else if let lastIndex = liveTranslations.indices.last, !liveTranslations[lastIndex].isFinal {
            liveTranslations[lastIndex].text = text
            liveTranslations[lastIndex].timestamp = chunk.timestamp
            liveTranslations[lastIndex].provider = chunk.provider
        } else {
            var next = chunk
            next.text = text
            next.isFinal = false
            liveTranslations.append(next)
        }

        if liveTranslations.count > 400 {
            liveTranslations.removeFirst(liveTranslations.count - 300)
        }
        refreshOverlayTranslation(using: chunk)
    }

    func recentDuplicateFinalTranslationIndex(normalizedText: String, now: Date) -> Int? {
        liveTranslations.indices.reversed().first { index in
            let item = liveTranslations[index]
            guard item.isFinal else { return false }
            let gap = now.timeIntervalSince(item.timestamp)
            guard gap >= 0, gap <= 8 else { return false }
            return normalizedRealtimeLine(item.text) == normalizedText
        }
    }

    func mergeTranscriptIfNeeded(at index: Int) {
        guard index > 0, index < liveTranscripts.count else { return }
        let previous = liveTranscripts[index - 1]
        let current = liveTranscripts[index]
        guard previous.isFinal, current.isFinal else { return }

        let gap = current.timestamp.timeIntervalSince(previous.timestamp)
        guard shouldMergeAdjacentLines(previous: previous.text, current: current.text, gap: gap) else { return }

        liveTranscripts[index - 1].text = stitchSentence(previous: previous.text, current: current.text)
        liveTranscripts[index - 1].timestamp = current.timestamp
        liveTranscripts.remove(at: index)
    }

    func mergeTranslationIfNeeded(at index: Int) {
        guard index > 0, index < liveTranslations.count else { return }
        let previous = liveTranslations[index - 1]
        let current = liveTranslations[index]
        guard previous.isFinal, current.isFinal else { return }

        let gap = current.timestamp.timeIntervalSince(previous.timestamp)
        guard shouldMergeAdjacentLines(previous: previous.text, current: current.text, gap: gap) else { return }

        liveTranslations[index - 1].text = stitchSentence(previous: previous.text, current: current.text)
        liveTranslations[index - 1].timestamp = current.timestamp
        liveTranslations.remove(at: index)
    }

    func shouldMergeAdjacentLines(previous: String, current: String, gap: TimeInterval) -> Bool {
        if gap < 0 || gap > 4.0 {
            return false
        }

        let prev = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prev.isEmpty, !next.isEmpty else { return false }
        guard !endsWithStrongStop(prev) else { return false }

        if startsWithConnector(next) {
            return true
        }
        if next.count <= 40 {
            return true
        }
        if prev.count <= 72 {
            return true
        }
        return gap <= 1.6
    }

    func endsWithStrongStop(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return ".?!。！？；;:：".contains(last)
    }

    func startsWithConnector(_ text: String) -> Bool {
        let lower = text.lowercased()
        let connectors = [
            "and", "but", "so", "because", "then", "which", "that",
            "to", "for", "of", "with", "if", "when", "while",
            "而", "并", "和", "并且", "因为", "所以", "然后", "但是", "且", "就", "又", "也",
        ]
        if connectors.contains(where: { lower.hasPrefix($0) }) {
            return true
        }
        if let first = text.first, first.isLowercase {
            return true
        }
        return false
    }

    func stitchSentence(previous: String, current: String) -> String {
        let prev = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prev.isEmpty else { return next }
        guard !next.isEmpty else { return prev }
        return shouldInsertSpaceBetween(previous: prev, current: next) ? "\(prev) \(next)" : "\(prev)\(next)"
    }

    func shouldInsertSpaceBetween(previous: String, current: String) -> Bool {
        guard let prevLast = previous.last, let nextFirst = current.first else {
            return false
        }
        return prevLast.isASCII && nextFirst.isASCII
    }

    func normalizedRealtimeLine(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        let collapsed = trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.lowercased()
    }

    func refreshOverlayTranscript(using _: TranscriptChunk) {
        overlayController.updateTranscriptHistory(Array(liveTranscripts.suffix(18)))
    }

    func refreshOverlayTranslation(using _: TranslationChunk) {
        overlayController.updateTranslationHistory(Array(liveTranslations.suffix(18)))
    }

    func updateAnswerHintIfNeeded(using chunk: TranscriptChunk) {
        guard answerHintsEnabled else { return }
        guard chunk.isFinal else { return }
        let text = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard looksLikeQuestion(text) else { return }

        let hint = composeAnswerHint(for: text)
        latestAnswerHint = hint
        hintRequestCount += 1
        hintInputTokenEstimate += estimateTokens(text)
        hintOutputTokenEstimate += estimateTokens(hint)
        overlayController.updateHint(hint)
    }

    func looksLikeQuestion(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("?")
            || lower.contains("what")
            || lower.contains("why")
            || lower.contains("how")
            || lower.contains("could you")
            || lower.contains("would you")
            || lower.contains("吗")
            || lower.contains("什么")
            || lower.contains("为什么")
            || lower.contains("怎么")
    }

    func composeAnswerHint(for question: String) -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        检测到提问：\(trimmed)
        建议回答结构：
        1. 先给一句结论（10秒内）。
        2. 给两点依据（事实/数据/案例）。
        3. 说明下一步动作与时间点。
        """
    }

    func estimateTokens(_ text: String) -> Int {
        let length = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        if length == 0 { return 0 }
        return max(1, Int(ceil(Double(length) / 4.0)))
    }

    func emptyTranslationChunk() -> TranslationChunk {
        TranslationChunk(
            text: "",
            isFinal: true,
            provider: speechPipelineSettings.translationProvider == .aliyun ? .aliyun : .microsoft
        )
    }

    func syncOverlayLayoutToCore(_ layout: LiveOverlayLayout) {
        overlayOpacity = layout.opacity
        overlayPositionText = layoutText(layout)

        if isStubRuntime { return }
        guard let coreClient else { return }

        do {
            let saved = try coreClient.saveLiveOverlayLayout(layout)
            overlayPositionText = layoutText(saved)
            if saved.opacity != overlayOpacity {
                overlayOpacity = saved.opacity
            }
        } catch {
            handleCoreError(operation: "save_live_overlay_layout", error: error)
        }
    }

    func persistOverlayMode() {
        if isStubRuntime { return }
        guard let coreClient else { return }

        do {
            let next = WindowModeState(
                alwaysOnTop: overlayAlwaysOnTop,
                transparent: true,
                undecorated: true,
                clickThrough: false,
                opacity: overlayOpacity
            )
            let applied = try coreClient.setLiveOverlayMode(next)
            overlayAlwaysOnTop = applied.alwaysOnTop
            overlayOpacity = applied.opacity
        } catch {
            handleCoreError(operation: "set_live_overlay_mode", error: error)
        }
    }

    func layoutText(_ layout: LiveOverlayLayout) -> String {
        "x:\(layout.x) y:\(layout.y) w:\(layout.width) h:\(layout.height)"
    }

    func providerKindForLlm(_ provider: LlmProviderKind) -> ProviderKind {
        switch provider {
        case .anthropic:
            return .claude
        case .openai:
            return .openai
        case .custom:
            return .customLlm
        }
    }

    func setStatus(_ value: String, tone: StatusTone) {
        statusText = value
        statusTone = tone
        appendRuntimeLog("[\(toneTag(tone))] \(value)")
    }

    func appendRuntimeLog(_ line: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        runtimeLogs.append("\(timestamp) \(line)")
        if runtimeLogs.count > 200 {
            runtimeLogs.removeFirst(runtimeLogs.count - 200)
        }
    }

    func toneTag(_ tone: StatusTone) -> String {
        switch tone {
        case .info:
            return "INFO"
        case .success:
            return "SUCCESS"
        case .warning:
            return "WARNING"
        case .error:
            return "ERROR"
        }
    }

    func handleCoreError(operation: String, error: Error) {
        if let coreError = error as? CoreInvokeError, coreError.code == "ffi_stub" {
            isStubRuntime = true
            setStatus("Preview mode enabled (FFI stub): runtime actions are simulated locally.", tone: .warning)
            return
        }

        setStatus("\(operation) failed: \(error.localizedDescription)", tone: .error)
    }
}
