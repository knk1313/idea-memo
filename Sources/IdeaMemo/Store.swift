import Foundation

/// メモ1件。本文は notes/ の md ファイルに、それ以外は index.json に保存する
struct Memo: Identifiable, Codable, Hashable {
    var id = UUID()
    var file: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var body: String = ""

    enum CodingKeys: String, CodingKey { case id, file, title, createdAt, updatedAt }
}

enum MemoText {
    static func title(of text: String) -> String {
        // 記号を取ったあとに文字が残る最初の行をタイトルにする（"#" だけの行は飛ばす）
        var t = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: #"^(#+|[-*+](\s+\[[ xX]\])?|\d+[.)]|>)\s*"#,
                                      with: "", options: .regularExpression) }
            .first { !$0.isEmpty } ?? ""
        if t.count > 40 { t = String(t.prefix(40)) + "…" }
        return t
    }
}

@MainActor
final class IdeaStore: ObservableObject {
    @Published private(set) var memos: [Memo] = []

    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/IdeaMemo", isDirectory: true)
    private static let rootKey = "rootPath"

    /// 保存先のフォルダ。中に notes/ と index.json を置く
    @Published private(set) var rootURL: URL = {
        if let p = UserDefaults.standard.string(forKey: rootKey) { return URL(fileURLWithPath: p, isDirectory: true) }
        return defaultRoot
    }()
    var notesURL: URL { rootURL.appendingPathComponent("notes", isDirectory: true) }
    var indexURL: URL { rootURL.appendingPathComponent("index.json") }

    private let fm = FileManager.default

    init() {
        try? fm.createDirectory(at: notesURL, withIntermediateDirectories: true)
        migrateLegacy()
        reload()
    }

    func url(of memo: Memo) -> URL { notesURL.appendingPathComponent(memo.file) }

    // MARK: 読み込み

    /// index.json と notes/ を読み直す。外で編集・追加された md も拾う
    func reload() {
        var result: [Memo] = []
        var known = Set<String>()
        for var m in loadIndex() {
            guard let body = try? String(contentsOf: url(of: m), encoding: .utf8) else { continue }
            m.body = body
            m.title = MemoText.title(of: body)
            known.insert(m.file)
            result.append(m)
        }
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey]
        let files = (try? fm.contentsOfDirectory(at: notesURL, includingPropertiesForKeys: keys)) ?? []
        for file in files where file.pathExtension == "md" && !known.contains(file.lastPathComponent) {
            guard let body = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let v = try? file.resourceValues(forKeys: Set(keys))
            result.append(Memo(file: file.lastPathComponent,
                               title: MemoText.title(of: body),
                               createdAt: v?.creationDate ?? Date(),
                               updatedAt: v?.contentModificationDate ?? Date(), body: body))
        }
        result.sort { $0.createdAt > $1.createdAt }
        if result != memos { memos = result }
        saveIndex()
    }

    // MARK: 変更

    @discardableResult
    func add(_ text: String) -> Memo? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        let now = Date()
        let title = MemoText.title(of: body)
        let memo = Memo(file: uniqueFileName(date: now, title: title), title: title,
                        createdAt: now, updatedAt: now, body: body)
        write(memo)
        memos.insert(memo, at: 0)
        saveIndex()
        return memo
    }

    func update(_ id: Memo.ID, body: String) {
        guard let i = memos.firstIndex(where: { $0.id == id }), memos[i].body != body else { return }
        memos[i].body = body
        memos[i].title = MemoText.title(of: body)
        memos[i].updatedAt = Date()
        write(memos[i])
        saveIndex()
    }

    /// ゴミ箱へ移す（Finder から戻せる）
    func delete(_ ids: Set<Memo.ID>) {
        for m in memos where ids.contains(m.id) {
            try? fm.trashItem(at: url(of: m), resultingItemURL: nil)
        }
        memos.removeAll { ids.contains($0.id) }
        saveIndex()
    }

    /// プレビューのチェックボックスを押したとき、その行の [ ] と [x] を入れ替える
    func toggleTask(_ id: Memo.ID, line: Int) {
        guard let memo = memos.first(where: { $0.id == id }) else { return }
        var lines = memo.body.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return }
        let l = lines[line]
        if let r = l.range(of: "[ ]") {
            lines[line] = l.replacingCharacters(in: r, with: "[x]")
        } else if let r = l.range(of: #"\[[xX]\]"#, options: .regularExpression) {
            lines[line] = l.replacingCharacters(in: r, with: "[ ]")
        }
        update(id, body: lines.joined(separator: "\n"))
    }

    // MARK: ファイル

    private func write(_ memo: Memo) {
        try? memo.body.write(to: url(of: memo), atomically: true, encoding: .utf8)
    }

    private func loadIndex(_ url: URL? = nil) -> [Memo] {
        guard let data = try? Data(contentsOf: url ?? indexURL) else { return [] }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return (try? d.decode([Memo].self, from: data)) ?? []
    }

    private func saveIndex() {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? e.encode(memos) { try? data.write(to: indexURL, options: .atomic) }
    }

    /// 例: "2026-11-06-194747.md"
    private func uniqueFileName(date: Date, title: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return uniqueName(base: f.string(from: date), in: notesURL)
    }

    /// dir の中で重ならない "base.md"（重なれば "base-2.md" …）
    private func uniqueName(base: String, in dir: URL) -> String {
        var name = base + ".md", n = 2
        while fm.fileExists(atPath: dir.appendingPathComponent(name).path) {
            name = "\(base)-\(n).md"; n += 1
        }
        return name
    }

    // MARK: 保存先の変更

    enum MoveError: LocalizedError {
        case sameFolder, insideNotes
        var errorDescription: String? {
            switch self {
            case .sameFolder: return "今と同じフォルダです。"
            case .insideNotes: return "今の notes フォルダの中は選べません。"
            }
        }
    }

    /// 保存先を newRoot に変え、今あるメモをすべて移す。
    /// 先に全件をコピーし、すべて成功してから元を消す（途中で失敗したらコピーを片付けて元のまま）。
    /// 移動先にすでに IdeaMemo のメモがあれば、合わせて1つにする。
    func changeRoot(to newRoot: URL) throws {
        let newRoot = newRoot.standardizedFileURL
        let oldRoot = rootURL.standardizedFileURL
        guard newRoot.path != oldRoot.path else { throw MoveError.sameFolder }
        guard newRoot.path != notesURL.standardizedFileURL.path,
              !newRoot.path.hasPrefix(notesURL.standardizedFileURL.path + "/") else { throw MoveError.insideNotes }

        reload() // 外で足された md も含めて最新にしてから移す
        let newNotes = newRoot.appendingPathComponent("notes", isDirectory: true)
        try fm.createDirectory(at: newNotes, withIntermediateDirectories: true)

        // 移動先にもともとあるメモ
        let newIndexURL = newRoot.appendingPathComponent("index.json")
        let existing = loadIndex(newIndexURL).filter {
            fm.fileExists(atPath: newNotes.appendingPathComponent($0.file).path)
        }
        var usedIDs = Set(existing.map(\.id))

        var copied: [URL] = []
        var moved: [Memo] = []
        do {
            for var m in memos {
                let base = (m.file as NSString).deletingPathExtension
                let name = uniqueName(base: base, in: newNotes)
                let dst = newNotes.appendingPathComponent(name)
                try fm.copyItem(at: url(of: m), to: dst)
                copied.append(dst)
                m.file = name
                if !usedIDs.insert(m.id).inserted { m.id = UUID() }
                moved.append(m)
            }
        } catch {
            copied.forEach { try? fm.removeItem(at: $0) }
            throw error
        }

        // 元を片付ける
        let oldFiles = memos.map { url(of: $0) }
        let oldIndex = indexURL, oldNotes = notesURL
        oldFiles.forEach { try? fm.removeItem(at: $0) }
        try? fm.removeItem(at: oldIndex)
        for dir in [oldNotes, oldRoot] where (try? fm.contentsOfDirectory(atPath: dir.path))?.isEmpty == true {
            try? fm.removeItem(at: dir)
        }

        rootURL = newRoot
        UserDefaults.standard.set(newRoot.path, forKey: Self.rootKey)
        memos = (moved + existing).sorted { $0.createdAt > $1.createdAt }
        saveIndex()
        reload()
    }

    /// v0.1 の ideas.json（1ファイルに全部）から移す。元のファイルは legacy-backup/ に残す
    private func migrateLegacy() {
        let legacy = rootURL.appendingPathComponent("ideas.json")
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: legacy) else { return }
        struct Old: Decodable { var id: UUID; var text: String; var createdAt: Date }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let olds = (try? d.decode([Old].self, from: data)) ?? []
        memos = olds.map { o in
            let title = MemoText.title(of: o.text)
            let m = Memo(id: o.id, file: uniqueFileName(date: o.createdAt, title: title), title: title,
                         createdAt: o.createdAt, updatedAt: o.createdAt,
                         body: o.text)
            write(m)
            return m
        }
        saveIndex()
        let backup = rootURL.appendingPathComponent("legacy-backup", isDirectory: true)
        try? fm.createDirectory(at: backup, withIntermediateDirectories: true)
        for name in ["ideas.json", "ideas.md"] {
            try? fm.moveItem(at: rootURL.appendingPathComponent(name), to: backup.appendingPathComponent(name))
        }
    }
}
