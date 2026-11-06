import AppKit

/// 入力中のテキストに Markdown の見た目をその場で付ける（記号は残して薄く表示する）
enum MarkdownStyler {
    private static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
    private static let heading = re(#"^(#{1,6})\s+"#)
    private static let task = re(#"^(\s*[-*+]\s+\[([ xX])\])\s"#)
    private static let listMarker = re(#"^(\s*(?:[-*+]|\d+[.)]))\s"#)
    private static let quote = re(#"^(\s*>)\s?"#)
    private static let rule = re(#"^\s*([-*_])(\s*\1){2,}\s*$"#)
    private static let inlineCode = re(#"`[^`\n]+`"#)
    private static let bold = re(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italic = re(#"(?<![*_\w])([*_])(?=\S)([^*_\n]+?)(?<=\S)\1(?![*_\w])"#)
    private static let strike = re(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let link = re(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)

    static var dim: NSColor { .tertiaryLabelColor }
    static var codeBackground: NSColor { NSColor.labelColor.withAlphaComponent(0.08) }

    static func baseAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = size * 0.25
        return [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.labelColor, .paragraphStyle: para]
    }

    /// 行の書き出しから決まる文字の大きさ（見出しなら大きく太く）。日本語の変換中の文字にも使う
    static func lineAttributes(for line: String, size: CGFloat) -> [NSAttributedString.Key: Any] {
        var a = baseAttributes(size: size)
        if let m = heading.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
            a[.font] = headingFont(level: m.range(at: 1).length, size: size)
        }
        return a
    }

    static func headingFont(level: Int, size: CGFloat) -> NSFont {
        let scale: CGFloat = [1.6, 1.35, 1.15][min(level, 3) - 1]
        return NSFont.systemFont(ofSize: size * scale, weight: .bold)
    }

    static func apply(to tv: NSTextView, size: CGFloat) {
        guard let storage = tv.textStorage, !tv.hasMarkedText() else { return }
        let ns = storage.string as NSString
        let base = baseAttributes(size: size)
        let mono = NSFont.monospacedSystemFont(ofSize: size * 0.88, weight: .regular)

        storage.beginEditing()
        storage.setAttributes(base, range: NSRange(location: 0, length: ns.length))

        var inCode = false
        var loc = 0
        while loc < ns.length {
            let lr = ns.lineRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(lr)
            let line = ns.substring(with: lr)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCode.toggle()
                storage.addAttributes([.font: mono, .foregroundColor: dim], range: lr)
                continue
            }
            if inCode {
                storage.addAttributes([.font: mono, .backgroundColor: codeBackground], range: lr)
                continue
            }
            styleLine(line, at: lr.location, in: storage, size: size, mono: mono)
        }
        storage.endEditing()
        tv.typingAttributes = base
    }

    private static func styleLine(_ line: String, at offset: Int, in s: NSTextStorage, size: CGFloat, mono: NSFont) {
        let len = (line as NSString).length
        let whole = NSRange(location: offset, length: len)
        func shift(_ r: NSRange) -> NSRange { NSRange(location: r.location + offset, length: r.length) }
        func first(_ re: NSRegularExpression) -> NSTextCheckingResult? {
            re.firstMatch(in: line, range: NSRange(location: 0, length: len))
        }

        if first(rule) != nil {
            s.addAttribute(.foregroundColor, value: dim, range: whole)
            return
        }
        if let m = first(heading) {
            s.addAttribute(.font, value: headingFont(level: m.range(at: 1).length, size: size), range: whole)
            s.addAttribute(.foregroundColor, value: dim, range: shift(m.range(at: 1)))
        } else if let m = first(task) {
            s.addAttributes([.foregroundColor: NSColor.controlAccentColor, .font: mono], range: shift(m.range(at: 1)))
            let ch = (line as NSString).substring(with: m.range(at: 2))
            if ch != " " {
                let rest = NSRange(location: offset + m.range.length, length: len - m.range.length)
                s.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                 .foregroundColor: NSColor.secondaryLabelColor], range: rest)
            }
        } else if let m = first(listMarker) {
            s.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: shift(m.range(at: 1)))
        } else if let m = first(quote) {
            s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: whole)
            s.addAttribute(.foregroundColor, value: dim, range: shift(m.range(at: 1)))
        }

        let all = NSRange(location: 0, length: len)
        for m in bold.matches(in: line, range: all) {
            let r = shift(m.range)
            s.enumerateAttribute(.font, in: r) { v, sub, _ in
                if let f = v as? NSFont { s.addAttribute(.font, value: NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask), range: sub) }
            }
            dimMarkers(m, markerLen: 2, offset: offset, in: s)
        }
        for m in italic.matches(in: line, range: all) {
            s.addAttribute(.obliqueness, value: 0.18, range: shift(m.range))
            dimMarkers(m, markerLen: 1, offset: offset, in: s)
        }
        for m in strike.matches(in: line, range: all) {
            s.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                             .foregroundColor: NSColor.secondaryLabelColor], range: shift(m.range))
            dimMarkers(m, markerLen: 2, offset: offset, in: s)
        }
        for m in link.matches(in: line, range: all) {
            s.addAttribute(.foregroundColor, value: dim, range: shift(m.range))
            s.addAttributes([.foregroundColor: NSColor.linkColor,
                             .underlineStyle: NSUnderlineStyle.single.rawValue], range: shift(m.range(at: 1)))
        }
        for m in inlineCode.matches(in: line, range: all) {
            s.addAttributes([.font: mono, .backgroundColor: codeBackground,
                             .foregroundColor: NSColor.systemPink], range: shift(m.range))
        }
    }

    private static func dimMarkers(_ m: NSTextCheckingResult, markerLen: Int, offset: Int, in s: NSTextStorage) {
        let r = m.range
        s.addAttribute(.foregroundColor, value: dim, range: NSRange(location: offset + r.location, length: markerLen))
        s.addAttribute(.foregroundColor, value: dim, range: NSRange(location: offset + NSMaxRange(r) - markerLen, length: markerLen))
    }
}
