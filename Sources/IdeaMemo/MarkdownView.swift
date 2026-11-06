import SwiftUI

enum MDBlock: Hashable {
    enum Marker: Hashable { case bullet, number(String), task(Bool) }
    case heading(level: Int, text: String)
    case paragraph(String)
    case listItem(indent: Int, marker: Marker, text: String, line: Int)
    case quote(String)
    case code(lang: String, text: String)
    case rule
}

enum MarkdownParser {
    static func parse(_ src: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        var para: [String] = [], quote: [String] = []
        var code: (lang: String, lines: [String])?

        func flush() {
            if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: "\n"))); para = [] }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))); quote = [] }
        }

        for (i, line) in src.components(separatedBy: "\n").enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if var c = code {
                if t.hasPrefix("```") {
                    blocks.append(.code(lang: c.lang, text: c.lines.joined(separator: "\n"))); code = nil
                } else { c.lines.append(line); code = c }
                continue
            }
            if t.hasPrefix("```") { flush(); code = (String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces), []); continue }
            if t.isEmpty { flush(); continue }
            if let m = groups(#"^(#{1,6})\s+(.*)$"#, t) { flush(); blocks.append(.heading(level: m[1].count, text: m[2])); continue }
            if t.range(of: #"^([-*_])(\s*\1){2,}$"#, options: .regularExpression) != nil { flush(); blocks.append(.rule); continue }
            if let m = groups(#"^>\s?(.*)$"#, t) {
                if !para.isEmpty { flush() }
                quote.append(m[1]); continue
            }
            let lead = line.prefix { $0 == " " || $0 == "\t" }
            let indent = lead.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
            if let m = groups(#"^[-*+]\s+\[([ xX])\]\s*(.*)$"#, t) {
                flush(); blocks.append(.listItem(indent: indent, marker: .task(m[1] != " "), text: m[2], line: i))
            } else if let m = groups(#"^[-*+]\s+(.*)$"#, t) {
                flush(); blocks.append(.listItem(indent: indent, marker: .bullet, text: m[1], line: i))
            } else if let m = groups(#"^(\d+)[.)]\s+(.*)$"#, t) {
                flush(); blocks.append(.listItem(indent: indent, marker: .number(m[1]), text: m[2], line: i))
            } else {
                if !quote.isEmpty { flush() }
                para.append(line)
            }
        }
        if let c = code { blocks.append(.code(lang: c.lang, text: c.lines.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    private static func groups(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
        }
    }

    /// 太字・斜体・コード・リンクなど行内の書式
    static func inline(_ s: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }
}

struct MarkdownView: View {
    let source: String
    var onToggleTask: ((Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownParser.parse(source).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            VStack(alignment: .leading, spacing: 4) {
                Text(MarkdownParser.inline(text))
                    .font(headingFont(level)).fontWeight(.bold)
                if level <= 2 { Divider() }
            }
            .padding(.top, level <= 2 ? 8 : 4)

        case .paragraph(let text):
            Text(MarkdownParser.inline(text)).font(.system(size: 14)).lineSpacing(4)

        case .listItem(let indent, let marker, let text, let line):
            let done: Bool = { if case .task(true) = marker { return true }; return false }()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                switch marker {
                case .bullet:
                    Text(indent % 2 == 0 ? "•" : "◦").foregroundStyle(.secondary)
                case .number(let n):
                    Text("\(n).").monospacedDigit().foregroundStyle(.secondary)
                case .task(let checked):
                    Button { onToggleTask?(line) } label: {
                        Image(systemName: checked ? "checkmark.square.fill" : "square")
                            .foregroundStyle(checked ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text(MarkdownParser.inline(text))
                    .strikethrough(done)
                    .foregroundStyle(done ? .secondary : .primary)
            }
            .font(.system(size: 14))
            .padding(.leading, CGFloat(indent) * 18 + 4)

        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(.secondary.opacity(0.4)).frame(width: 3)
                Text(MarkdownParser.inline(text)).foregroundStyle(.secondary).font(.system(size: 14))
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code(let lang, let text):
            VStack(alignment: .leading, spacing: 4) {
                if !lang.isEmpty { Text(lang).font(.caption2).foregroundStyle(.secondary) }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(text).font(.system(size: 12.5, design: .monospaced))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

        case .rule:
            Divider().padding(.vertical, 4)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 24)
        case 2: return .system(size: 20)
        case 3: return .system(size: 17)
        default: return .system(size: 15)
        }
    }
}
