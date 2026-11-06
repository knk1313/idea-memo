import AppKit
import Carbon.HIToolbox
import SwiftUI

/// ⏎ と ⌃⏎ の動きを変えられるテキスト入力欄
final class MemoNSTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var placeholder = ""
    var baseSize: CGFloat = 14

    private static let listRE = try! NSRegularExpression(
        pattern: #"^(\s*)(?:([-*+])\s+\[[ xX]\]|([-*+])|(\d+)([.)])|(>))\s"#)

    override func keyDown(with event: NSEvent) {
        // 日本語入力の変換中は、⏎ も esc も変換の操作として扱う
        if hasMarkedText() { super.keyDown(with: event); return }
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if !event.modifierFlags.isDisjoint(with: [.control, .shift]) || onSubmit == nil {
                insertSmartNewline()
                return
            }
            onSubmit?(); return
        case kVK_Escape:
            if let onCancel { onCancel(); return }
        case kVK_Tab:
            if indentListLine(outdent: event.modifierFlags.contains(.shift)) { return }
        default: break
        }
        super.keyDown(with: event)
    }

    // MARK: Notion 風の入力補助

    private var currentLine: (range: NSRange, text: String) {
        let ns = string as NSString
        let lr = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        var text = ns.substring(with: lr)
        if text.hasSuffix("\n") { text.removeLast() }
        return (NSRange(location: lr.location, length: (text as NSString).length), text)
    }

    private func listMatch(_ line: String) -> NSTextCheckingResult? {
        Self.listRE.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
    }

    /// 改行。リストの行なら次の行にも記号を続け、中身が空の項目なら記号を消してリストを抜ける
    func insertSmartNewline() {
        let (lineRange, line) = currentLine
        let l = line as NSString
        guard let m = listMatch(line), selectedRange().location >= lineRange.location + m.range.length else {
            insertText("\n", replacementRange: selectedRange())
            return
        }
        if l.substring(from: m.range.length).trimmingCharacters(in: .whitespaces).isEmpty {
            insertText("", replacementRange: lineRange)
            return
        }
        func g(_ i: Int) -> String? {
            m.range(at: i).location == NSNotFound ? nil : l.substring(with: m.range(at: i))
        }
        let next: String
        if let b = g(2) { next = b + " [ ] " }
        else if let b = g(3) { next = b + " " }
        else if let n = g(4), let p = g(5) { next = "\((Int(n) ?? 0) + 1)\(p) " }
        else { next = "> " }
        insertText("\n" + g(1)! + next, replacementRange: selectedRange())
    }

    /// リストの行で Tab なら字下げ、⇧Tab なら字下げを戻す。リストの行でなければ false
    private func indentListLine(outdent: Bool) -> Bool {
        let (lineRange, line) = currentLine
        guard listMatch(line) != nil else { return false }
        let sel = selectedRange()
        if outdent {
            let n = line.hasPrefix("  ") ? 2 : (line.hasPrefix("\t") ? 1 : 0)
            guard n > 0 else { return true }
            replace(NSRange(location: lineRange.location, length: n), with: "")
            setSelectedRange(NSRange(location: max(lineRange.location, sel.location - n), length: sel.length))
        } else {
            replace(NSRange(location: lineRange.location, length: 0), with: "  ")
            setSelectedRange(NSRange(location: sel.location + 2, length: sel.length))
        }
        return true
    }

    private func replace(_ r: NSRange, with s: String) {
        guard shouldChangeText(in: r, replacementString: s) else { return }
        textStorage?.replaceCharacters(in: r, with: s)
        didChangeText()
    }

    /// 日本語の変換中の文字も、見出しの行なら見出しの大きさで出す
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if !hasMarkedText() {
            typingAttributes = MarkdownStyler.lineAttributes(for: currentLine.text, size: baseSize)
        }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    /// 行頭で "[] " と打ったらチェックボックス "- [ ] " に変える
    override func insertText(_ text: Any, replacementRange: NSRange) {
        super.insertText(text, replacementRange: replacementRange)
        let typed = (text as? String) ?? (text as? NSAttributedString)?.string
        guard typed == " ", !hasMarkedText() else { return }
        let (lineRange, line) = currentLine
        let cursor = selectedRange().location - lineRange.location
        let before = (line as NSString).substring(to: cursor)
        guard before.range(of: #"^\s*\[\] $"#, options: .regularExpression) != nil else { return }
        let indentLen = (before as NSString).length - 3
        let r = NSRange(location: lineRange.location + indentLen, length: 3)
        replace(r, with: "- [ ] ")
        setSelectedRange(NSRange(location: NSMaxRange(r) + 3, length: 0))
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
                             y: textContainerInset.height)
        placeholder.draw(at: origin, withAttributes: [
            .font: NSFont.systemFont(ofSize: baseSize),
            .foregroundColor: NSColor.placeholderTextColor,
        ])
    }
}

struct MemoTextView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: 14)
    var placeholder = ""
    /// 値が変わるたびにフォーカスを当てる
    var focusToken = 0
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let tv = MemoNSTextView(frame: .zero)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.baseSize = font.pointSize
        tv.typingAttributes = MarkdownStyler.baseAttributes(size: font.pointSize)
        tv.delegate = context.coordinator
        scroll.documentView = tv
        apply(to: tv, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? MemoNSTextView else { return }
        context.coordinator.parent = self
        apply(to: tv, context: context)
    }

    private func apply(to tv: MemoNSTextView, context: Context) {
        tv.baseSize = font.pointSize
        tv.placeholder = placeholder
        tv.onSubmit = onSubmit
        tv.onCancel = onCancel
        if tv.string != text {
            tv.string = text
            MarkdownStyler.apply(to: tv, size: font.pointSize)
            context.coordinator.reportHeight(tv)
        }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MemoTextView
        var lastFocusToken = Int.min
        var lastHeight: CGFloat = -1
        init(_ parent: MemoTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            MarkdownStyler.apply(to: tv, size: parent.font.pointSize)
            parent.text = tv.string
            reportHeight(tv, immediately: true)
        }

        /// 入力中（immediately）はその場で知らせる。SwiftUI の更新中に呼ばれたときは次の周回に回す
        func reportHeight(_ tv: NSTextView, immediately: Bool = false) {
            guard let cb = parent.onHeightChange, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let h = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
            guard h != lastHeight else { return }
            lastHeight = h
            if immediately { cb(h) } else { DispatchQueue.main.async { cb(h) } }
        }
    }
}
