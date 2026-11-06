import AppKit
import SwiftUI

/// Spotlight のように画面中央に浮かぶ入力パネル
final class QuickPanel: NSPanel {
    init(store: IdeaStore) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 640, height: 120),
                   styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        let view = QuickInputView(store: store,
                                  dismiss: { [weak self] in self?.close() },
                                  onTextHeight: { [weak self] h in self?.fit(textHeight: h) })
        // 枠と中身の高さが一瞬ずれても揺れて見えないよう、中身は上に寄せる
        let host = NSHostingView(rootView: view.frame(maxHeight: .infinity, alignment: .top))
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    private static let screenMargin: CGFloat = 16

    /// 開いたときの上端。高さが変わってもここを基準にする（縮んだら元の位置に戻る）
    private var anchorTop: CGFloat = 0
    /// 最後にこちらで置いた上端。ずれていれば利用者がドラッグで動かしたとみなす
    private var lastPlacedTop: CGFloat = 0
    /// 入力欄以外（余白・案内の行）の高さ。開くたびに実際の大きさから測り直す
    private var chromeHeight: CGFloat = 66
    private var textHeight: CGFloat = 28

    static func clampTextHeight(_ h: CGFloat) -> CGFloat { min(max(h, 28), maxTextHeight) }

    /// 入力欄の高さが変わったら、その場で枠の高さを合わせる（あとから追いかけるとカクつくため）
    func fit(textHeight h: CGFloat) {
        textHeight = Self.clampTextHeight(h)
        place(height: textHeight + chromeHeight)
    }

    /// 上端は anchorTop に置いて下に伸ばす。画面の下にはみ出すときだけ上にずらす
    private func place(height: CGFloat) {
        if isVisible, abs(frame.maxY - lastPlacedTop) > 1 { anchorTop = frame.maxY }
        var f = frame
        f.size.height = height
        f.origin.y = anchorTop - height
        if let vf = (screen ?? NSScreen.main)?.visibleFrame {
            let m = Self.screenMargin
            if f.minY < vf.minY + m { f.origin.y = vf.minY + m }
            if f.maxY > vf.maxY - m { f.origin.y = vf.maxY - m - f.height }
        }
        lastPlacedTop = f.maxY
        guard f != frame else { return }
        setFrame(f, display: true)
        invalidateShadow()
    }

    /// 入力欄が伸びてよい高さ。画面の高さから、案内の行と余白のぶんを引いた残り全部
    static var maxTextHeight: CGFloat {
        let h = (NSScreen.main?.visibleFrame.height ?? 900) - screenMargin * 2 - 110
        return max(120, h.rounded())
    }

    override func resignKey() {
        super.resignKey()
        close() // ほかをクリックしたら閉じる（書きかけは残る）
    }

    func show() {
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            anchorTop = f.midY + f.height * 0.18
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: anchorTop - frame.height))
        }
        lastPlacedTop = anchorTop
        NotificationCenter.default.post(name: .quickPanelWillShow, object: nil)
        if let host = contentView {
            host.layoutSubtreeIfNeeded()
            let h = host.intrinsicContentSize.height
            if h > textHeight { chromeHeight = h - textHeight }
        }
        place(height: textHeight + chromeHeight)
        makeKeyAndOrderFront(nil)
    }
}

extension Notification.Name {
    static let quickPanelWillShow = Notification.Name("quickPanelWillShow")
    static let toggleEditMode = Notification.Name("toggleEditMode")
    static let changeStorage = Notification.Name("changeStorage")
}

struct QuickInputView: View {
    @ObservedObject var store: IdeaStore
    var dismiss: () -> Void
    var onTextHeight: (CGFloat) -> Void
    @State private var text = ""
    @State private var savedFlash = false
    @State private var focusToken = 0
    @State private var textHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: savedFlash ? "checkmark.circle.fill" : "lightbulb")
                    .font(.system(size: 22))
                    .foregroundStyle(savedFlash ? .green : .yellow)
                    .padding(.top, 1)
                MemoTextView(text: $text, font: .systemFont(ofSize: 20),
                             placeholder: "思いついたことをそのまま書く…",
                             focusToken: focusToken,
                             onSubmit: save, onCancel: dismiss,
                             onHeightChange: { textHeight = $0; onTextHeight($0) })
                    .frame(height: QuickPanel.clampTextHeight(textHeight))
            }
            HStack(spacing: 14) {
                hint("⏎", "保存")
                hint("⌃⏎ / ⇧⏎", "改行")
                hint("⌘L", "メモ一覧")
                hint("esc", "閉じる")
                Spacer()
            }
            .font(.caption)
        }
        .padding(18)
        .frame(width: 640)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onReceive(NotificationCenter.default.publisher(for: .quickPanelWillShow)) { _ in
            savedFlash = false
            focusToken += 1
        }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
        }
        .foregroundStyle(.secondary)
    }

    private func save() {
        guard store.add(text) != nil else { return }
        text = ""
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
    }
}

