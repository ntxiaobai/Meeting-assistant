import SwiftUI

struct MenuBarQuickPanel: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meeting Assistant")
                .font(.system(size: 14, weight: .semibold))

            Button(store.sessionRunning ? "停止会话" : "开始会话") {
                if store.sessionRunning {
                    store.stopSession()
                } else {
                    store.startSession()
                }
            }
            .buttonStyle(.borderedProminent)

            Divider()

            Picker("输入源", selection: $store.speechPipelineSettings.audioSourceMode) {
                ForEach(AudioSourceMode.allCases) { mode in
                    Text(modeTitle(mode)).tag(mode)
                }
            }
            .onChange(of: store.speechPipelineSettings.audioSourceMode) {
                store.quickSwitchAudioSource(store.speechPipelineSettings.audioSourceMode)
            }

            Picker("ASR", selection: $store.speechPipelineSettings.asrProvider) {
                ForEach(AsrProviderChoice.allCases) { provider in
                    Text(provider.rawValue.capitalized).tag(provider)
                }
            }
            .onChange(of: store.speechPipelineSettings.asrProvider) {
                store.quickSwitchAsrProvider(store.speechPipelineSettings.asrProvider)
            }

            Divider()

            Button("打开主窗口") {
                store.activateMainWindow()
            }

            Button("退出应用") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
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
}
