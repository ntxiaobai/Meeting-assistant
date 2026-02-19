import CoreBridge
import SwiftUI

private enum DashboardPane: String, CaseIterable, Identifiable {
    case dashboard
    case audio
    case translation
    case hints
    case overlay
    case preferences
    case live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:
            return "仪表板"
        case .audio:
            return "语音链路"
        case .translation:
            return "翻译"
        case .hints:
            return "回答提示"
        case .overlay:
            return "悬浮窗"
        case .preferences:
            return "偏好设置"
        case .live:
            return "实时流"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:
            return "square.grid.2x2"
        case .audio:
            return "waveform"
        case .translation:
            return "character.bubble"
        case .hints:
            return "lightbulb"
        case .overlay:
            return "rectangle.on.rectangle"
        case .preferences:
            return "gearshape"
        case .live:
            return "waveform.path.ecg"
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedPane: DashboardPane = .dashboard

    private let columns = [
        GridItem(.flexible(minimum: 360), spacing: 16),
        GridItem(.flexible(minimum: 360), spacing: 16),
    ]

    var body: some View {
        ZStack {
            backgroundLayer

            HStack(spacing: 16) {
                sidebar
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        heroCard
                        mainContent
                        runtimeCard
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(18)
        }
        .frame(minWidth: 1180, minHeight: 780)
    }

    private var backgroundLayer: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            Circle()
                .fill(Color.blue.opacity(0.14))
                .frame(width: 420, height: 420)
                .blur(radius: 80)
                .offset(x: -300, y: -220)
            Circle()
                .fill(Color.teal.opacity(0.14))
                .frame(width: 460, height: 460)
                .blur(radius: 92)
                .offset(x: 380, y: -260)
            Circle()
                .fill(Color.indigo.opacity(0.1))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(x: 220, y: 260)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Meeting Assistant")
                        .font(.system(size: 15, weight: .semibold))
                    Text(store.isStubRuntime ? "Preview Mode" : "Native Session")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(store.isStubRuntime ? .orange : .green)
                }
            }
            .padding(.bottom, 8)

            VStack(spacing: 6) {
                ForEach(DashboardPane.allCases) { pane in
                    Button {
                        selectedPane = pane
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: pane.icon)
                                .frame(width: 18)
                            Text(pane.title)
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedPane == pane ? Color.white.opacity(0.62) : Color.clear)
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("会话状态")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 230)
        .glassCardStyle()
    }

    private var heroCard: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("会议助手控制台")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("语音链路 + 翻译 + 回答提示 + 悬浮窗")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Button(store.sessionRunning ? "停止会话" : "启动会话") {
                        if store.sessionRunning {
                            store.stopSession()
                        } else {
                            store.startSession()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("刷新") {
                        store.refreshBootstrap()
                    }
                    .buttonStyle(.bordered)
                }
                HStack(spacing: 8) {
                    Button("显示悬浮窗") { store.openOverlay() }
                        .buttonStyle(.bordered)
                    Button("隐藏") { store.closeOverlay() }
                        .buttonStyle(.bordered)
                }
                Toggle("回答提示", isOn: $store.answerHintsEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: store.answerHintsEnabled) {
                        store.setAnswerHintsEnabled(store.answerHintsEnabled)
                    }
            }
        }
        .glassCardStyle()
    }

    @ViewBuilder
    private var mainContent: some View {
        switch selectedPane {
        case .dashboard:
            compactLiveFeedCard
            LazyVGrid(columns: columns, spacing: 16) {
                speechOverviewCard
                translationOverviewCard
                hintsOverviewCard
                overlayCard
            }
        case .audio:
            LazyVGrid(columns: columns, spacing: 16) {
                audioPipelineCard
                providerSecretsCard
            }
        case .translation:
            translationCard
        case .hints:
            hintsCard
        case .overlay:
            overlayCard
        case .preferences:
            preferencesCard
        case .live:
            liveFeedCard
        }
    }

    private var compactLiveFeedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("实时转写 / 翻译")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("T:\(store.liveTranscripts.count)  R:\(store.liveTranslations.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("原文")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if store.liveTranscripts.isEmpty {
                                Text("等待语音输入…")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(store.liveTranscripts.suffix(8)) { item in
                                    Text(item.text)
                                        .font(.system(size: 12, weight: item.isFinal ? .medium : .regular))
                                        .foregroundStyle(
                                            Color.black.opacity(
                                                liveLineOpacity(
                                                    timestamp: item.timestamp,
                                                    isCurrent: item.id == store.liveTranscripts.last?.id
                                                )
                                            )
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            Color.clear.frame(height: 1).id("compact-transcript-bottom")
                        }
                    }
                    .onAppear {
                        autoScrollToBottom(proxy: proxy, anchorId: "compact-transcript-bottom")
                    }
                    .onChange(of: store.liveTranscripts.last?.timestamp) {
                        autoScrollToBottom(proxy: proxy, anchorId: "compact-transcript-bottom")
                    }
                    .onChange(of: store.liveTranscripts.count) {
                        autoScrollToBottom(proxy: proxy, anchorId: "compact-transcript-bottom")
                    }
                }
                .frame(minHeight: 84, maxHeight: 110)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("翻译")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if store.liveTranslations.isEmpty {
                                Text("等待翻译输出…")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(store.liveTranslations.suffix(8)) { item in
                                    Text(item.text)
                                        .font(.system(size: 12, weight: item.isFinal ? .medium : .regular))
                                        .foregroundStyle(
                                            Color.black.opacity(
                                                liveLineOpacity(
                                                    timestamp: item.timestamp,
                                                    isCurrent: item.id == store.liveTranslations.last?.id
                                                )
                                            )
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            Color.clear.frame(height: 1).id("compact-translation-bottom")
                        }
                    }
                    .onAppear {
                        autoScrollToBottom(proxy: proxy, anchorId: "compact-translation-bottom")
                    }
                    .onChange(of: store.liveTranslations.last?.timestamp) {
                        autoScrollToBottom(proxy: proxy, anchorId: "compact-translation-bottom")
                    }
                    .onChange(of: store.liveTranslations.count) {
                        autoScrollToBottom(proxy: proxy, anchorId: "compact-translation-bottom")
                    }
                }
                .frame(minHeight: 84, maxHeight: 110)
            }
        }
        .glassCardStyle()
    }

    private var speechOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("语音链路")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                statusChip(text: speechLinkStatusText, color: speechLinkStatusColor)
            }

            Toggle("链路开关", isOn: sessionBinding)
                .toggleStyle(.switch)

            Text("ASR: \(store.speechPipelineSettings.asrProvider.rawValue.capitalized)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Segments: \(store.speechSegmentCount)  Token估算: \(store.speechTokenEstimate)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Button("打开语音链路设置") {
                selectedPane = .audio
            }
            .buttonStyle(.bordered)
        }
        .glassCardStyle()
    }

    private var translationOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("翻译")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                statusChip(text: translationLinkStatusText, color: translationLinkStatusColor)
            }

            Toggle(
                "翻译开关",
                isOn: Binding(
                    get: { store.speechPipelineSettings.translationEnabled },
                    set: { value in
                        store.setTranslationEnabled(value)
                    }
                )
            )
            .toggleStyle(.switch)

            Text("Provider: \(store.speechPipelineSettings.translationProvider.rawValue.capitalized)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Segments: \(store.translationSegmentCount)  Token估算: \(store.translationTokenEstimate)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Button("打开翻译设置") {
                selectedPane = .translation
            }
            .buttonStyle(.bordered)
        }
        .glassCardStyle()
    }

    private var hintsOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("回答提示")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                statusChip(text: hintLinkStatusText, color: hintLinkStatusColor)
            }

            Toggle("提示开关", isOn: $store.answerHintsEnabled)
                .toggleStyle(.switch)
                .onChange(of: store.answerHintsEnabled) {
                    store.setAnswerHintsEnabled(store.answerHintsEnabled)
                }

            Text("Model: \(store.llmProvider.rawValue.capitalized) / \(store.llmModel)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("Requests: \(store.hintRequestCount)  In: \(store.hintInputTokenEstimate)  Out: \(store.hintOutputTokenEstimate)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Button("打开提示模型设置") {
                selectedPane = .hints
            }
            .buttonStyle(.bordered)
        }
        .glassCardStyle()
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("应用偏好")
                .font(.system(size: 18, weight: .semibold))

            labeled {
                Text("语言")
            } content: {
                Picker("Language", selection: $store.locale) {
                    ForEach(LocaleCode.allCases) { value in
                        Text(localeTitle(value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .onChange(of: store.locale) {
                    store.applyUserPreferences()
                }
            }

            labeled {
                Text("主题")
            } content: {
                Picker("Theme", selection: $store.themeMode) {
                    ForEach(ThemeMode.allCases) { value in
                        Text(themeTitle(value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .onChange(of: store.themeMode) {
                    store.applyUserPreferences()
                }
            }

            Text("偏好设置会立即生效。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .glassCardStyle()
    }

    private var hintsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("提示模型")
                .font(.system(size: 18, weight: .semibold))

            Toggle("开启回答提示", isOn: $store.answerHintsEnabled)
                .toggleStyle(.switch)
                .onChange(of: store.answerHintsEnabled) {
                    store.setAnswerHintsEnabled(store.answerHintsEnabled)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text("最近提示")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(store.latestAnswerHint.isEmpty ? "检测到问题后会在这里显示回答提示。" : store.latestAnswerHint)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(store.latestAnswerHint.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 78, maxHeight: 108)
            }

            labeled {
                Text("Provider")
            } content: {
                Picker("Provider", selection: $store.llmProvider) {
                    ForEach(LlmProviderKind.allCases) { value in
                        Text(llmProviderTitle(value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
                .onChange(of: store.llmProvider) {
                    store.restoreLlmApiKeyDraftForCurrentProvider()
                    store.saveLlmSettingsDraftSilently()
                }
            }

            labeled {
                Text("Model")
            } content: {
                TextField("Model", text: $store.llmModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 260)
                    .onChange(of: store.llmModel) {
                        store.saveLlmSettingsDraftSilently()
                    }
            }

            if store.llmProvider == .custom {
                labeled {
                    Text("Base URL")
                } content: {
                    TextField("https://api.example.com", text: $store.llmBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 260)
                        .onChange(of: store.llmBaseURL) {
                            store.saveLlmSettingsDraftSilently()
                        }
                }

                labeled {
                    Text("API Format")
                } content: {
                    Picker("API Format", selection: $store.llmApiFormat) {
                        ForEach(LlmApiFormat.allCases) { value in
                            Text(llmApiFormatTitle(value)).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    .onChange(of: store.llmApiFormat) {
                        store.saveLlmSettingsDraftSilently()
                    }
                }
            }

            HStack(spacing: 10) {
                SecureField("API key（存入 Keychain）", text: $store.llmApiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                Button("保存 Key") {
                    store.saveLlmApiKey()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button(store.hintsApiTestTesting ? "测试中..." : "测试提示模型连接") {
                    store.testHintsApiConnection()
                }
                .buttonStyle(.bordered)
                .disabled(store.hintsApiTestTesting)

                Text(store.hintsApiTestMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(testStatusColor(store.hintsApiTestTone))
                    .lineLimit(2)
            }

            Button("保存 LLM 设置") {
                store.saveLlmSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .glassCardStyle()
    }

    private var audioPipelineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("语音链路")
                .font(.system(size: 18, weight: .semibold))

            labeled {
                Text("ASR")
            } content: {
                Picker("ASR Provider", selection: $store.speechPipelineSettings.asrProvider) {
                    ForEach(AsrProviderChoice.allCases) { provider in
                        Text(provider.rawValue.capitalized).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: store.speechPipelineSettings.asrProvider) {
                    store.saveSpeechProviderSettingsSilently()
                }
            }

            labeled {
                Text("输入源")
            } content: {
                Picker("Audio Source", selection: $store.speechPipelineSettings.audioSourceMode) {
                    ForEach(AudioSourceMode.allCases) { mode in
                        Text(modeTitle(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: store.speechPipelineSettings.audioSourceMode) {
                    store.saveSpeechProviderSettingsSilently()
                }
            }

            Button("打开屏幕录制权限设置") {
                store.openScreenRecordingSettings()
            }
            .buttonStyle(.bordered)

            Divider().opacity(0.5)

            Text("Deepgram")
                .font(.system(size: 15, weight: .semibold))
            HStack(spacing: 10) {
                TextField("Language", text: $store.deepgramConfig.language)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .onChange(of: store.deepgramConfig.language) {
                        store.saveSpeechProviderSettingsSilently()
                    }
                Toggle("Interim", isOn: $store.deepgramConfig.interimEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: store.deepgramConfig.interimEnabled) {
                        store.saveSpeechProviderSettingsSilently()
                    }
            }
            HStack(spacing: 10) {
                SecureField("Deepgram API Key", text: $store.deepgramApiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                Button("保存 Deepgram Key") {
                    store.saveDeepgramSecret()
                }
                .buttonStyle(.bordered)
            }
            Text(store.deepgramSecretConfigured ? "Deepgram Key: 已配置" : "Deepgram Key: 未配置")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(store.deepgramSecretConfigured ? .green : .secondary)

            HStack(spacing: 8) {
                Button(store.speechApiTesting ? "测试中..." : "测试语音链路连接") {
                    store.testSpeechApiConnection()
                }
                .buttonStyle(.bordered)
                .disabled(store.speechApiTesting)

                Text(store.speechApiTestMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(testStatusColor(store.speechApiTestTone))
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button("保存语音链路配置") {
                    store.saveSpeechProviderSettings()
                }
                .buttonStyle(.borderedProminent)
                Button(store.sessionRunning ? "停止会话" : "启动会话") {
                    if store.sessionRunning {
                        store.stopSession()
                    } else {
                        store.startSession()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .glassCardStyle()
    }

    private var providerSecretsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("凭据集合")
                .font(.system(size: 18, weight: .semibold))

            if store.secretProfiles.isEmpty {
                Text("暂无凭据集合，保存任意 Key 后会自动创建默认集合。")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            } else {
                labeled {
                    Text("当前")
                } content: {
                    Picker("Key Profile", selection: $store.activeSecretProfileId) {
                        ForEach(store.secretProfiles) { profile in
                            Text(profile.id == store.activeSecretProfileId ? "\(profile.name) (当前)" : profile.name)
                                .tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                    .onChange(of: store.activeSecretProfileId) {
                        store.selectSecretProfile(store.activeSecretProfileId)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.secretProfiles.prefix(6)) { profile in
                        Text(profileDetail(profile))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(profile.id == store.activeSecretProfileId ? .primary : .secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("新集合名称", text: $store.secretProfileNameDraft)
                    .textFieldStyle(.roundedBorder)
                Button("新建并切换") {
                    store.createSecretProfile()
                }
                .buttonStyle(.bordered)
            }

            Divider().opacity(0.5)

            Text("阿里云 ASR（可选）")
                .font(.system(size: 15, weight: .semibold))
            HStack(spacing: 10) {
                SecureField("AccessKeyId", text: $store.aliyunAccessKeyIdDraft)
                    .textFieldStyle(.roundedBorder)
                SecureField("AccessKeySecret", text: $store.aliyunAccessKeySecretDraft)
                    .textFieldStyle(.roundedBorder)
                SecureField("AppKey", text: $store.aliyunAppKeyDraft)
                    .textFieldStyle(.roundedBorder)
            }
            Button("保存阿里云凭据") {
                store.saveAliyunSecrets()
            }
            .buttonStyle(.bordered)
            Text(store.aliyunSecretConfigured ? "阿里云凭据: 已配置" : "阿里云凭据: 未配置")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(store.aliyunSecretConfigured ? .green : .secondary)
        }
        .glassCardStyle()
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("翻译")
                .font(.system(size: 18, weight: .semibold))

            Toggle(
                "启用翻译",
                isOn: Binding(
                    get: { store.speechPipelineSettings.translationEnabled },
                    set: { value in
                        store.setTranslationEnabled(value)
                    }
                )
            )
            .toggleStyle(.switch)

            labeled {
                Text("Provider")
            } content: {
                Picker("Translation Provider", selection: $store.speechPipelineSettings.translationProvider) {
                    ForEach(TranslationProviderChoice.allCases) { provider in
                        Text(provider.rawValue.capitalized).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                .onChange(of: store.speechPipelineSettings.translationProvider) {
                    store.saveSpeechProviderSettingsSilently()
                }
            }

            HStack(spacing: 10) {
                TextField("源语言（例：en）", text: $store.aliyunConfig.sourceLanguage)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: store.aliyunConfig.sourceLanguage) {
                        store.saveSpeechProviderSettingsSilently()
                    }
                TextField("目标语言（例：cn）", text: $store.aliyunConfig.targetLanguage)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: store.aliyunConfig.targetLanguage) {
                        store.saveSpeechProviderSettingsSilently()
                    }
            }

            Divider().opacity(0.5)

            Text("Microsoft Translator")
                .font(.system(size: 15, weight: .semibold))
            HStack(spacing: 10) {
                TextField("Endpoint", text: $store.microsoftConfig.endpoint)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: store.microsoftConfig.endpoint) {
                        store.saveSpeechProviderSettingsSilently()
                    }
                TextField("Region（可留空）", text: $store.microsoftConfig.region)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onChange(of: store.microsoftConfig.region) {
                        store.saveSpeechProviderSettingsSilently()
                    }
            }
            HStack(spacing: 10) {
                SecureField("Microsoft Translator API Key", text: $store.microsoftTranslatorApiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                Button("保存 Microsoft Key") {
                    store.saveMicrosoftTranslatorSecret()
                }
                .buttonStyle(.bordered)
            }
            Text(store.microsoftSecretConfigured ? "Microsoft 凭据: 已配置" : "Microsoft 凭据: 未配置")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(store.microsoftSecretConfigured ? .green : .secondary)

            HStack(spacing: 8) {
                Button(store.translationApiTestTesting ? "测试中..." : "测试翻译链路连接") {
                    store.testTranslationApiConnection()
                }
                .buttonStyle(.bordered)
                .disabled(store.translationApiTestTesting)

                Text(store.translationApiTestMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(testStatusColor(store.translationApiTestTone))
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button("保存翻译配置") {
                    store.saveSpeechProviderSettings()
                }
                .buttonStyle(.borderedProminent)
                Button("从钥匙串刷新状态") {
                    store.reloadSecretStatusFromKeychain()
                }
                .buttonStyle(.bordered)
            }
        }
        .glassCardStyle()
    }

    private var overlayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("悬浮窗")
                .font(.system(size: 18, weight: .semibold))

            HStack(spacing: 10) {
                Text("透明度")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                Slider(value: $store.overlayOpacity, in: 0.35 ... 1.0, step: 0.01)
                    .onChange(of: store.overlayOpacity) {
                        store.applyOverlayOpacity()
                    }
                Text(String(format: "%.2f", store.overlayOpacity))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .frame(width: 48, alignment: .trailing)
            }

            Toggle("Always On Top", isOn: $store.overlayAlwaysOnTop)
                .toggleStyle(.switch)
                .onChange(of: store.overlayAlwaysOnTop) {
                    store.applyAlwaysOnTop()
                }

            Toggle("在悬浮窗显示回答提示", isOn: $store.answerHintsEnabled)
                .toggleStyle(.switch)
                .onChange(of: store.answerHintsEnabled) {
                    store.setAnswerHintsEnabled(store.answerHintsEnabled)
                }

            labeled {
                Text("可见性")
            } content: {
                Text(store.overlayVisible ? "Visible" : "Hidden")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(store.overlayVisible ? .green : .secondary)
            }

            labeled {
                Text("位置")
            } content: {
                Text(store.overlayPositionText)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("显示") { store.openOverlay() }
                    .buttonStyle(.borderedProminent)
                Button("隐藏") { store.closeOverlay() }
                    .buttonStyle(.bordered)
                Button("重置位置") { store.resetOverlayLayout() }
                    .buttonStyle(.bordered)
            }
        }
        .glassCardStyle()
    }

    private var liveFeedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("实时转写 / 翻译")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Text("Transcript: \(store.liveTranscripts.count)  Translation: \(store.liveTranslations.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcript")
                        .font(.system(size: 13, weight: .semibold))
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(store.liveTranscripts.suffix(50)) { item in
                                    Text(item.text)
                                        .font(.system(size: 12, weight: item.isFinal ? .semibold : .regular))
                                        .foregroundStyle(
                                            Color.black.opacity(
                                                liveLineOpacity(
                                                    timestamp: item.timestamp,
                                                    isCurrent: item.id == store.liveTranscripts.last?.id
                                                )
                                            )
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Color.clear.frame(height: 1).id("live-transcript-bottom")
                            }
                        }
                        .onAppear {
                            autoScrollToBottom(proxy: proxy, anchorId: "live-transcript-bottom")
                        }
                        .onChange(of: store.liveTranscripts.last?.timestamp) {
                            autoScrollToBottom(proxy: proxy, anchorId: "live-transcript-bottom")
                        }
                        .onChange(of: store.liveTranscripts.count) {
                            autoScrollToBottom(proxy: proxy, anchorId: "live-transcript-bottom")
                        }
                    }
                    .frame(minHeight: 180, maxHeight: 220)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Translation")
                        .font(.system(size: 13, weight: .semibold))
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(store.liveTranslations.suffix(50)) { item in
                                    Text(item.text)
                                        .font(.system(size: 12, weight: item.isFinal ? .semibold : .regular))
                                        .foregroundStyle(
                                            Color.black.opacity(
                                                liveLineOpacity(
                                                    timestamp: item.timestamp,
                                                    isCurrent: item.id == store.liveTranslations.last?.id
                                                )
                                            )
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Color.clear.frame(height: 1).id("live-translation-bottom")
                            }
                        }
                        .onAppear {
                            autoScrollToBottom(proxy: proxy, anchorId: "live-translation-bottom")
                        }
                        .onChange(of: store.liveTranslations.last?.timestamp) {
                            autoScrollToBottom(proxy: proxy, anchorId: "live-translation-bottom")
                        }
                        .onChange(of: store.liveTranslations.count) {
                            autoScrollToBottom(proxy: proxy, anchorId: "live-translation-bottom")
                        }
                    }
                    .frame(minHeight: 180, maxHeight: 220)
                }
            }
        }
        .glassCardStyle()
    }

    private var runtimeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: store.statusSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(statusColor.opacity(0.18)))

                Text(store.statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .textSelection(.enabled)

                Spacer()

                Text(store.runtimeStatus.sessionState.rawValue.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.45)))
            }

            HStack {
                Text("Runtime Logs")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("复制日志") {
                    store.copyRuntimeLogs()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(store.runtimeLogs.suffix(14).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(minHeight: 88, maxHeight: 128)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        )
    }

    private func labeled<Label: View, Content: View>(
        @ViewBuilder label: () -> Label,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center) {
            label()
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func autoScrollToBottom(proxy: ScrollViewProxy, anchorId: String) {
        DispatchQueue.main.async {
            proxy.scrollTo(anchorId, anchor: .bottom)
        }
    }

    private func liveLineOpacity(timestamp: Date, isCurrent: Bool) -> Double {
        if isCurrent {
            return 1.0
        }
        let age = Date().timeIntervalSince(timestamp)
        switch age {
        case ..<2:
            return 0.84
        case ..<6:
            return 0.68
        case ..<12:
            return 0.52
        case ..<20:
            return 0.38
        default:
            return 0.24
        }
    }

    private var statusLabel: String {
        store.statusLabel
    }

    private var statusColor: Color {
        switch store.statusTone {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var sessionBinding: Binding<Bool> {
        Binding(
            get: { store.sessionRunning },
            set: { value in
                if value {
                    store.startSession()
                } else {
                    store.stopSession()
                }
            }
        )
    }

    private var speechLinkStatusText: String {
        let active = Set(store.runtimeStatus.activeProviders)
        if store.sessionRunning && (!active.isDisjoint(with: ["deepgram", "aliyun"])) {
            return "已连接"
        }
        if store.deepgramSecretConfigured || store.aliyunSecretConfigured {
            return "就绪"
        }
        return "未配置"
    }

    private var speechLinkStatusColor: Color {
        switch speechLinkStatusText {
        case "已连接":
            return .green
        case "就绪":
            return .orange
        default:
            return .secondary
        }
    }

    private var translationLinkStatusText: String {
        if !store.speechPipelineSettings.translationEnabled {
            return "已关闭"
        }
        let active = Set(store.runtimeStatus.activeProviders)
        if !active.isDisjoint(with: ["microsoft_translation", "aliyun_translation"]) {
            return "已连接"
        }
        let configured = store.speechPipelineSettings.translationProvider == .microsoft
            ? store.microsoftSecretConfigured
            : store.aliyunSecretConfigured
        return configured ? "就绪" : "未配置"
    }

    private var translationLinkStatusColor: Color {
        switch translationLinkStatusText {
        case "已连接":
            return .green
        case "就绪":
            return .orange
        case "已关闭":
            return .secondary
        default:
            return .secondary
        }
    }

    private var hintLinkStatusText: String {
        if !store.answerHintsEnabled {
            return "已关闭"
        }
        if store.llmModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "未配置"
        }
        return "就绪"
    }

    private var hintLinkStatusColor: Color {
        switch hintLinkStatusText {
        case "就绪":
            return .green
        case "已关闭":
            return .secondary
        default:
            return .secondary
        }
    }

    private func statusChip(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private func localeTitle(_ value: LocaleCode) -> String {
        switch value {
        case .zhCN:
            return "中文"
        case .enUS:
            return "English"
        }
    }

    private func themeTitle(_ value: ThemeMode) -> String {
        switch value {
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        case .system:
            return "System"
        }
    }

    private func llmProviderTitle(_ value: LlmProviderKind) -> String {
        switch value {
        case .anthropic:
            return "Anthropic"
        case .openai:
            return "OpenAI"
        case .custom:
            return "Custom"
        }
    }

    private func llmApiFormatTitle(_ value: LlmApiFormat) -> String {
        switch value {
        case .anthropic:
            return "Anthropic"
        case .openai:
            return "OpenAI"
        }
    }

    private func modeTitle(_ mode: AudioSourceMode) -> String {
        switch mode {
        case .system:
            return "System"
        case .microphone:
            return "Microphone"
        case .mixed:
            return "Mixed"
        }
    }

    private func profileDetail(_ profile: ProviderSecretProfileSummary) -> String {
        let deepgram = profile.hasDeepgram ? "DG:yes" : "DG:no"
        let aliyun = profile.hasAliyun ? "AL:yes" : "AL:no"
        let microsoft = profile.hasMicrosoft ? "MS:yes" : "MS:no"
        let updated = profile.updatedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(profile.name) | \(deepgram) \(aliyun) \(microsoft) | updated \(updated)"
    }

    private func testStatusColor(_ tone: AppStore.StatusTone) -> Color {
        switch tone {
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        case .info:
            return .secondary
        }
    }
}

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.38), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 6)
    }
}

extension View {
    func glassCardStyle() -> some View {
        modifier(GlassCardModifier())
    }
}
