import SwiftUI

struct SpeechProviderSettingsCard: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("语音链路设置")
                .font(.system(size: 18, weight: .semibold))

            labeled("ASR Provider") {
                Picker("ASR Provider", selection: $store.speechPipelineSettings.asrProvider) {
                    ForEach(AsrProviderChoice.allCases) { provider in
                        Text(provider.rawValue.capitalized).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }

            labeled("翻译 Provider") {
                Picker("Translation Provider", selection: $store.speechPipelineSettings.translationProvider) {
                    ForEach(TranslationProviderChoice.allCases) { provider in
                        Text(provider.rawValue.capitalized).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }

            labeled("声纹 Provider") {
                Picker("Voiceprint Provider", selection: $store.speechPipelineSettings.voiceprintProvider) {
                    ForEach(VoiceprintProviderChoice.allCases) { provider in
                        Text(providerTitle(provider)).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }

            Toggle("启用声纹识别（本轮仅保留配置）", isOn: $store.speechPipelineSettings.voiceprintEnabled)
                .toggleStyle(.switch)

            labeled("音频来源") {
                Picker("Audio Source", selection: $store.speechPipelineSettings.audioSourceMode) {
                    ForEach(AudioSourceMode.allCases) { mode in
                        Text(modeTitle(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            Button("打开屏幕录制权限设置") {
                store.openScreenRecordingSettings()
            }
            .buttonStyle(.bordered)

            Divider().opacity(0.5)

            Text("本地凭据集合")
                .font(.system(size: 15, weight: .semibold))
            if store.secretProfiles.isEmpty {
                Text("暂无凭据集合，保存任意 Key 后将自动创建默认集合。")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            } else {
                labeled("当前集合") {
                    Picker("Key Profile", selection: $store.activeSecretProfileId) {
                        ForEach(store.secretProfiles) { profile in
                            Text(profileLabel(profile)).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 260)
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
            HStack(spacing: 10) {
                TextField("新集合名称（例如：客户A-美东）", text: $store.secretProfileNameDraft)
                    .textFieldStyle(.roundedBorder)
                Button("新建并切换") {
                    store.createSecretProfile()
                }
                .buttonStyle(.bordered)
            }

            Divider().opacity(0.5)

            Text("Deepgram")
                .font(.system(size: 15, weight: .semibold))
            labeled("Language") {
                TextField("en", text: $store.deepgramConfig.language)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            Toggle("Interim Results", isOn: $store.deepgramConfig.interimEnabled)
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

            Divider().opacity(0.5)

            Text("语言设置（转写/翻译）")
                .font(.system(size: 15, weight: .semibold))
            HStack(spacing: 10) {
                TextField("源语言（例：en）", text: $store.aliyunConfig.sourceLanguage)
                    .textFieldStyle(.roundedBorder)
                TextField("目标语言（例：cn）", text: $store.aliyunConfig.targetLanguage)
                    .textFieldStyle(.roundedBorder)
            }

            Divider().opacity(0.5)

            Text("Microsoft Translator")
                .font(.system(size: 15, weight: .semibold))
            HStack(spacing: 10) {
                TextField("Endpoint", text: $store.microsoftConfig.endpoint)
                    .textFieldStyle(.roundedBorder)
                TextField("Region（可留空，global 资源）", text: $store.microsoftConfig.region)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
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

            Divider().opacity(0.5)

            Text("阿里云听悟（仅当 ASR/翻译选择 Aliyun 时需要）")
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

            Button("从钥匙串刷新状态") {
                store.reloadSecretStatusFromKeychain()
            }
            .buttonStyle(.bordered)

            HStack(spacing: 8) {
                Button("保存语音配置") {
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

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            content()
            Spacer()
        }
    }

    private func providerTitle(_ provider: VoiceprintProviderChoice) -> String {
        switch provider {
        case .deepgram:
            return "Deepgram"
        case .aliyun:
            return "Aliyun"
        case .off:
            return "Off"
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

    private func profileLabel(_ profile: ProviderSecretProfileSummary) -> String {
        if profile.id == store.activeSecretProfileId {
            return "\(profile.name) (当前)"
        }
        return profile.name
    }

    private func profileDetail(_ profile: ProviderSecretProfileSummary) -> String {
        let deepgram = profile.hasDeepgram ? "DG:yes" : "DG:no"
        let aliyun = profile.hasAliyun ? "AL:yes" : "AL:no"
        let microsoft = profile.hasMicrosoft ? "MS:yes" : "MS:no"
        let updated = profile.updatedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(profile.name) | \(deepgram) \(aliyun) \(microsoft) | updated \(updated)"
    }
}
