import SwiftUI

struct IdeaListView: View {
    @ObservedObject var store: IdeaStore
    @State private var query = ""
    @State private var selection: Memo.ID?
    @State private var editing = false
    /// 左のチェックで選んだメモ
    @State private var checked = Set<Memo.ID>()
    /// 削除の確認待ちのメモ
    @State private var pendingDelete: [Memo] = []

    private var filtered: [Memo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.memos }
        return store.memos.filter { $0.body.localizedCaseInsensitiveContains(q) }
    }

    private var deleteTitle: String {
        pendingDelete.count == 1
            ? "「\(pendingDelete[0].title)」を削除しますか？"
            : "\(pendingDelete.count)件のメモを削除しますか？"
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                TextField("検索", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(10)
                List(filtered, selection: $selection) { memo in
                    MemoRow(memo: memo, isChecked: checked.contains(memo.id)) {
                        if checked.contains(memo.id) { checked.remove(memo.id) } else { checked.insert(memo.id) }
                    }
                    .tag(memo.id)
                    .contextMenu {
                        Button("本文をコピー") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(memo.body, forType: .string)
                        }
                        Button("Finderで表示") {
                            NSWorkspace.shared.activateFileViewerSelecting([store.url(of: memo)])
                        }
                        Divider()
                        Button("削除…", role: .destructive) { pendingDelete = [memo] }
                    }
                }
                .listStyle(.sidebar)
                .onDeleteCommand(perform: requestDeleteFromKeyboard)

                if !checked.isEmpty {
                    Divider()
                    HStack(spacing: 10) {
                        Text("\(checked.count)件を選択中").font(.callout)
                        Spacer()
                        Button(checked.count == filtered.count ? "選択を解除" : "すべて選択") {
                            if checked.count == filtered.count { checked.removeAll() }
                            else { checked = Set(filtered.map(\.id)) }
                        }
                        .buttonStyle(.link)
                        Button(role: .destructive) {
                            pendingDelete = store.memos.filter { checked.contains($0.id) }
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                        .buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                }

                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(store.rootURL.path.replacingOccurrences(
                        of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                        .lineLimit(1).truncationMode(.middle)
                        .help(store.rootURL.path)
                    Spacer()
                    Button("変更…") {
                        NotificationCenter.default.post(name: .changeStorage, object: nil)
                    }
                    .buttonStyle(.link)
                }
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 7)
            }
            .frame(minWidth: 240, idealWidth: 290, maxWidth: 400)

            Group {
                if let id = selection, let memo = store.memos.first(where: { $0.id == id }) {
                    MemoDetailView(store: store, memo: memo, editing: $editing,
                                   onDelete: { pendingDelete = [memo] }).id(memo.id)
                } else {
                    ContentUnavailableView(store.memos.isEmpty ? "まだメモがありません" : "メモを選んでください",
                                           systemImage: "lightbulb",
                                           description: Text("⌃⌘Space か ⌘N でどこからでも書けます"))
                }
            }
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 480)
        .onAppear(perform: fixSelection)
        .onChange(of: store.memos) {
            checked.formIntersection(store.memos.map(\.id))
            fixSelection()
        }
        .onChange(of: query) { fixSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .toggleEditMode)) { _ in
            if selection != nil { editing.toggle() }
        }
        .confirmationDialog(deleteTitle,
                            isPresented: Binding(get: { !pendingDelete.isEmpty },
                                                 set: { if !$0 { pendingDelete = [] } })) {
            Button("ゴミ箱に移動", role: .destructive) {
                editing = false
                store.delete(Set(pendingDelete.map(\.id)))
                pendingDelete = []
            }
            Button("キャンセル", role: .cancel) { pendingDelete = [] }
        } message: {
            Text("mdファイルはゴミ箱に移るので、あとからFinderで戻せます。")
        }
    }

    /// Delete キー：チェックがあればそれらを、なければ開いているメモを消す
    private func requestDeleteFromKeyboard() {
        if !checked.isEmpty {
            pendingDelete = store.memos.filter { checked.contains($0.id) }
        } else if let m = store.memos.first(where: { $0.id == selection }) {
            pendingDelete = [m]
        }
    }

    private func fixSelection() {
        if selection == nil || !filtered.contains(where: { $0.id == selection }) {
            selection = filtered.first?.id
        }
    }
}

private struct MemoRow: View {
    let memo: Memo
    let isChecked: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: toggle) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .help(isChecked ? "選択を外す" : "選択する")
            rowContent
        }
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(memo.title.isEmpty ? "（無題）" : memo.title)
                .fontWeight(.semibold).lineLimit(1)
            Text(memo.createdAt, format: .relative(presentation: .named))
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

private struct MemoDetailView: View {
    @ObservedObject var store: IdeaStore
    let memo: Memo
    @Binding var editing: Bool
    var onDelete: () -> Void
    @State private var draft = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(memo.createdAt, format: .dateTime.year().month().day().weekday().hour().minute())
                    if memo.updatedAt.timeIntervalSince(memo.createdAt) > 60 {
                        Text("更新 \(memo.updatedAt.formatted(.relative(presentation: .named)))")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $editing) {
                    Text("プレビュー").tag(false)
                    Text("編集").tag(true)
                }
                .pickerStyle(.segmented).fixedSize()
                .help("⌘E で切り替え")
                Button { NSWorkspace.shared.activateFileViewerSelecting([store.url(of: memo)]) } label: {
                    Image(systemName: "folder")
                }
                .help("Finderで表示")
                Button(action: onDelete) { Image(systemName: "trash") }
                    .help("削除（一覧で Delete キーでも）")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 20).padding(.vertical, 10)
            Divider()

            if editing {
                MemoTextView(text: $draft, font: .systemFont(ofSize: 15), focusToken: 1)
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .onChange(of: draft) { scheduleSave() }
            } else {
                ScrollView {
                    if memo.body.isEmpty {
                        Text("（空のメモ）").foregroundStyle(.secondary).padding(28)
                    } else {
                        MarkdownView(source: memo.body) { line in store.toggleTask(memo.id, line: line) }
                            .padding(28)
                    }
                }
            }
        }
        .onAppear { draft = memo.body }
        .onChange(of: memo.body) { if !editing { draft = memo.body } }
        .onChange(of: editing) { if !editing { saveNow() } }
        .onDisappear(perform: saveNow)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { saveNow() }
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        store.update(memo.id, body: draft)
    }
}
