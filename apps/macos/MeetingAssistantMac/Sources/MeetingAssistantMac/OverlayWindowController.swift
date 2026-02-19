import AppKit
import CoreBridge
import SwiftUI

@MainActor
final class OverlayWindowController: NSObject, ObservableObject, NSWindowDelegate {
    private static let defaultsKey = "meeting_assistant.mac.overlay_layout.v1"

    private var panel: NSPanel?
    private var layout: LiveOverlayLayout
    private let contentModel = OverlayContentModel()
    var onLayoutChanged: ((LiveOverlayLayout) -> Void)?
    var onCloseRequested: (() -> Void)?
    var onToggleHintsRequested: ((Bool) -> Void)?

    override init() {
        self.layout = Self.loadLayout() ?? Self.defaultLayout()
        super.init()
    }

    func currentLayout() -> LiveOverlayLayout {
        layout
    }

    func configure(initialLayout: LiveOverlayLayout) {
        let sanitized = sanitize(initialLayout)
        layout = sanitized
        persistLayout()
        if let panel {
            applyToPanel(panel, layout: sanitized)
        }
    }

    func show() {
        let panel = ensurePanel()
        let sanitized = sanitize(layout)
        layout = sanitized
        applyToPanel(panel, layout: sanitized)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func resetToDefaultLayout(notify: Bool = true) -> LiveOverlayLayout {
        let next = sanitize(Self.defaultLayout())
        layout = next
        if let panel {
            applyToPanel(panel, layout: next)
        }
        persistLayout()
        if notify {
            onLayoutChanged?(next)
        }
        return next
    }

    func setOpacity(_ value: Double, notify: Bool = true) {
        var next = layout
        next.opacity = clampOpacity(value)
        layout = next
        if let panel {
            panel.alphaValue = CGFloat(next.opacity)
        }
        persistLayout()
        if notify {
            onLayoutChanged?(next)
        }
    }

    func setAlwaysOnTop(_ value: Bool) {
        let panel = ensurePanel()
        panel.level = value ? .statusBar : .normal
    }

    func clearContent() {
        contentModel.transcriptText = ""
        contentModel.translationText = ""
        contentModel.transcriptLines = []
        contentModel.translationLines = []
        contentModel.transcriptIsFinal = false
        contentModel.translationIsFinal = false
        contentModel.hintText = ""
    }

    func updateTranscript(_ chunk: TranscriptChunk) {
        contentModel.transcriptText = chunk.text
        contentModel.transcriptLines = linesFromText(chunk.text, timestamp: chunk.timestamp)
        contentModel.transcriptIsFinal = chunk.isFinal
    }

    func updateTranslation(_ chunk: TranslationChunk) {
        contentModel.translationText = chunk.text
        contentModel.translationLines = linesFromText(chunk.text, timestamp: chunk.timestamp)
        contentModel.translationIsFinal = chunk.isFinal
    }

    func updateTranscriptHistory(_ chunks: [TranscriptChunk]) {
        let mapped = chunks.compactMap { chunk -> OverlayContentModel.TimedLine? in
            let text = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return OverlayContentModel.TimedLine(id: chunk.id, text: text, timestamp: chunk.timestamp)
        }
        contentModel.transcriptLines = mapped
        contentModel.transcriptText = mapped.map(\.text).joined(separator: "\n")
        contentModel.transcriptIsFinal = chunks.last?.isFinal ?? false
    }

    func updateTranslationHistory(_ chunks: [TranslationChunk]) {
        let mapped = chunks.compactMap { chunk -> OverlayContentModel.TimedLine? in
            let text = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return OverlayContentModel.TimedLine(id: chunk.id, text: text, timestamp: chunk.timestamp)
        }
        contentModel.translationLines = mapped
        contentModel.translationText = mapped.map(\.text).joined(separator: "\n")
        contentModel.translationIsFinal = chunks.last?.isFinal ?? false
    }

    func setHintsEnabled(_ enabled: Bool) {
        contentModel.hintsEnabled = enabled
    }

    func updateHint(_ text: String) {
        contentModel.hintText = text
    }

    private func linesFromText(_ text: String, timestamp: Date) -> [OverlayContentModel.TimedLine] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return trimmed
            .split(whereSeparator: \.isNewline)
            .map { line in
                OverlayContentModel.TimedLine(id: UUID(), text: String(line), timestamp: timestamp)
            }
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(
                x: CGFloat(layout.x),
                y: CGFloat(layout.y),
                width: CGFloat(layout.width),
                height: CGFloat(layout.height)
            ),
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Meeting Assistant Overlay"
        panel.level = .statusBar
        panel.delegate = self
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.alphaValue = CGFloat(clampOpacity(layout.opacity))
        panel.contentView = NSHostingView(
            rootView: OverlayContentView(
                model: contentModel,
                onClose: { [weak self] in
                    self?.onCloseRequested?()
                },
                onToggleHints: { [weak self] enabled in
                    self?.onToggleHintsRequested?(enabled)
                }
            )
        )
        self.panel = panel
        return panel
    }

    private func applyToPanel(_ panel: NSPanel, layout: LiveOverlayLayout) {
        let currentFrame = panel.frame
        let targetFrame = NSRect(
            x: CGFloat(layout.x),
            y: CGFloat(layout.y),
            width: CGFloat(layout.width),
            height: CGFloat(layout.height)
        )
        if currentFrame != targetFrame {
            panel.setFrame(targetFrame, display: true)
        }
        panel.alphaValue = CGFloat(clampOpacity(layout.opacity))
    }

    private func synchronizeFromPanel(notify: Bool) {
        guard let panel else {
            return
        }
        let frame = panel.frame
        var next = LiveOverlayLayout(
            opacity: Double(panel.alphaValue),
            x: Int(frame.origin.x.rounded()),
            y: Int(frame.origin.y.rounded()),
            width: UInt32(max(560, Int(frame.size.width.rounded()))),
            height: UInt32(max(260, Int(frame.size.height.rounded()))),
            anchorScreen: panel.screen?.localizedName
        )
        next = sanitize(next)
        layout = next
        persistLayout()
        if notify {
            onLayoutChanged?(next)
        }
    }

    func windowDidMove(_ notification: Notification) {
        synchronizeFromPanel(notify: true)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        synchronizeFromPanel(notify: true)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        synchronizeFromPanel(notify: true)
    }

    func windowDidResize(_ notification: Notification) {
        synchronizeFromPanel(notify: false)
    }

    private func sanitize(_ input: LiveOverlayLayout) -> LiveOverlayLayout {
        var next = input
        next.opacity = clampOpacity(next.opacity)

        let screens = NSScreen.screens
        guard let screen = preferredScreen(for: input.anchorScreen, screens: screens) else {
            return next
        }

        let visible = screen.visibleFrame
        let width = CGFloat(max(560, min(Int(next.width), Int(visible.width))))
        let height = CGFloat(max(260, min(Int(next.height), Int(visible.height))))

        let minX = visible.minX
        let minY = visible.minY
        let maxX = max(minX, visible.maxX - width)
        let maxY = max(minY, visible.maxY - height)

        let clampedX = max(minX, min(CGFloat(next.x), maxX))
        let clampedY = max(minY, min(CGFloat(next.y), maxY))

        next.width = UInt32(width.rounded())
        next.height = UInt32(height.rounded())
        next.x = Int(clampedX.rounded())
        next.y = Int(clampedY.rounded())
        next.anchorScreen = screen.localizedName
        return next
    }

    private func preferredScreen(for anchorScreen: String?, screens: [NSScreen]) -> NSScreen? {
        if let anchorScreen, let matched = screens.first(where: { $0.localizedName == anchorScreen }) {
            return matched
        }
        return NSScreen.main ?? screens.first
    }

    private func persistLayout() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(layout) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func loadLayout() -> LiveOverlayLayout? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode(LiveOverlayLayout.self, from: data)
    }

    private static func defaultLayout() -> LiveOverlayLayout {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return LiveOverlayLayout(opacity: 0.86, x: 980, y: 110, width: 920, height: 480, anchorScreen: nil)
        }
        let visible = screen.visibleFrame
        let width: CGFloat = min(920, max(560, visible.width * 0.46))
        let height: CGFloat = min(480, max(280, visible.height * 0.34))
        let x = Int((visible.maxX - width - 24).rounded())
        let y = Int((visible.maxY - height - 24).rounded())

        return LiveOverlayLayout(
            opacity: 0.86,
            x: x,
            y: y,
            width: UInt32(width.rounded()),
            height: UInt32(height.rounded()),
            anchorScreen: screen.localizedName
        )
    }

    private func clampOpacity(_ value: Double) -> Double {
        max(0.35, min(1.0, value))
    }
}

private final class OverlayContentModel: ObservableObject {
    struct TimedLine: Identifiable {
        var id: UUID
        var text: String
        var timestamp: Date
    }

    @Published var transcriptText: String = ""
    @Published var translationText: String = ""
    @Published var transcriptLines: [TimedLine] = []
    @Published var translationLines: [TimedLine] = []
    @Published var transcriptIsFinal: Bool = false
    @Published var translationIsFinal: Bool = false
    @Published var hintsEnabled: Bool = true
    @Published var hintText: String = ""
}

private struct OverlayContentView: View {
    @ObservedObject var model: OverlayContentModel
    let onClose: () -> Void
    let onToggleHints: (Bool) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                WindowDragHandle()
                    .frame(width: 120, height: 28)
                Text("Drag to move")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle(
                    isOn: Binding(
                        get: { model.hintsEnabled },
                        set: { value in
                            model.hintsEnabled = value
                            onToggleHints(value)
                        }
                    )
                ) {
                    Text("提示")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .frame(width: 86)

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 10) {
                livePanelCard(
                    title: "Original",
                    lines: model.transcriptLines,
                    placeholder: "实时原文会在这里展示",
                    isFinal: model.transcriptIsFinal
                )
                livePanelCard(
                    title: "Translation",
                    lines: model.translationLines,
                    placeholder: "实时翻译会在这里展示",
                    isFinal: model.translationIsFinal
                )
            }

            if model.hintsEnabled {
                hintPanelCard(
                    title: "Answer Hints",
                    text: model.hintText,
                    placeholder: "检测到问题后会展示回答提示",
                    isFinal: true
                )
                .frame(minHeight: 104, maxHeight: 140)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func livePanelCard(
        title: String,
        lines: [OverlayContentModel.TimedLine],
        placeholder: String,
        isFinal: Bool
    ) -> some View {
        let bottomAnchorId = "overlay-bottom-\(title)"
        let visibleLines = Array(lines.suffix(18))
        let latestId = visibleLines.last?.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(isFinal ? "FINAL" : "INTERIM")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isFinal ? .green : .secondary)
            }
            RoundedRectangle(cornerRadius: 10)
                .fill(.thinMaterial)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 6) {
                                if visibleLines.isEmpty {
                                    Text(placeholder)
                                        .font(.system(size: 21, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                } else {
                                    ForEach(visibleLines) { line in
                                        Text(line.text)
                                            .font(.system(size: 21, weight: .medium))
                                            .foregroundStyle(
                                                Color.black.opacity(
                                                    liveLineOpacity(
                                                        timestamp: line.timestamp,
                                                        isCurrent: line.id == latestId
                                                    )
                                                )
                                            )
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.top, 10)
                                }
                                Color.clear
                                    .frame(height: 1)
                                    .id(bottomAnchorId)
                            }
                        }
                        .onAppear {
                            scrollToBottom(proxy, anchorId: bottomAnchorId)
                        }
                        .onChange(of: visibleLines.last?.id) {
                            scrollToBottom(proxy, anchorId: bottomAnchorId)
                        }
                        .onChange(of: visibleLines.count) {
                            scrollToBottom(proxy, anchorId: bottomAnchorId)
                        }
                    }
                }
        }
    }

    private func hintPanelCard(title: String, text: String, placeholder: String, isFinal: Bool) -> some View {
        let bottomAnchorId = "overlay-bottom-\(title)"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(isFinal ? "FINAL" : "INTERIM")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isFinal ? .green : .secondary)
            }
            RoundedRectangle(cornerRadius: 10)
                .fill(.thinMaterial)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : text)
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                Color.clear
                                    .frame(height: 1)
                                    .id(bottomAnchorId)
                            }
                        }
                        .onAppear {
                            scrollToBottom(proxy, anchorId: bottomAnchorId)
                        }
                        .onChange(of: text) {
                            scrollToBottom(proxy, anchorId: bottomAnchorId)
                        }
                    }
                }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, anchorId: String) {
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
            return 0.82
        case ..<6:
            return 0.66
        case ..<12:
            return 0.5
        case ..<20:
            return 0.36
        default:
            return 0.22
        }
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        DragHandleNSView()
    }

    func updateNSView(_: NSView, context _: Context) {}
}

private final class DragHandleNSView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.35).cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
