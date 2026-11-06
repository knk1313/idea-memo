import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = IdeaStore()
    var statusItem: NSStatusItem!
    var panel: QuickPanel!
    var listWindow: NSWindow?
    var hotKey: HotKey?
    var ctrlReturnMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = QuickPanel(store: store)
        buildMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: "IdeaMemo")
        let menu = NSMenu()
        menu.addItem(item("メモする  (⌃⌘Space)", #selector(showPanel)))
        menu.addItem(item("メモ一覧", #selector(showList), "l"))
        menu.addItem(.separator())
        menu.addItem(item("保存先を変更…", #selector(changeStorage)))
        menu.addItem(item("保存先をFinderで開く", #selector(openStorage)))
        menu.addItem(.separator())
        menu.addItem(withTitle: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        // ⌃⌘Space
        // ⌃⏎ は macOS の「コンテキストメニューを表示」に取られるので、先に受け取って改行にする
        ctrlReturnMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isReturn = event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter)
            guard isReturn,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control,
                  let tv = NSApp.keyWindow?.firstResponder as? MemoNSTextView,
                  !tv.hasMarkedText() else { return event }
            tv.insertSmartNewline()
            return nil
        }

        NotificationCenter.default.addObserver(forName: .changeStorage, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.changeStorage() }
        }

        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | controlKey)) { [weak self] in
            Task { @MainActor in self?.togglePanel() }
        }
    }

    /// Dock に出ないアプリでも ⌘C/⌘V/⌘Z や ⌘L が効くようにメニューを用意する
    private func buildMainMenu() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "IdeaMemoを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = NSMenu(title: "ファイル")
        file.addItem(item("新規メモ", #selector(showPanel), "n"))
        file.addItem(item("メモ一覧", #selector(showList), "l"))
        file.addItem(item("プレビュー／編集を切り替え", #selector(toggleEdit), "e"))
        file.addItem(.separator())
        file.addItem(item("保存先を変更…", #selector(changeStorage)))
        file.addItem(withTitle: "閉じる", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = NSMenu(title: "編集")
        edit.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "やり直す", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        for sub in [app, file, edit] {
            let holder = NSMenuItem()
            holder.submenu = sub
            main.addItem(holder)
        }
        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    func togglePanel() {
        panel.isVisible ? panel.close() : showPanel()
    }

    @objc func showPanel() {
        NSApp.activate(ignoringOtherApps: true)
        panel.show()
    }

    @objc func showList() {
        panel.close()
        if listWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "アイデアメモ"
            w.contentView = NSHostingView(rootView: IdeaListView(store: store))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setFrameAutosaveName("IdeaMemoList")
            if !w.setFrameUsingName("IdeaMemoList") { w.center() }
            listWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        listWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func openStorage() {
        NSWorkspace.shared.open(store.rootURL)
    }

    /// フォルダを選ばせて、メモごと移す
    @objc func changeStorage() {
        panel.close()
        NSApp.activate(ignoringOtherApps: true)
        let open = NSOpenPanel()
        open.title = "メモの保存先を選ぶ"
        open.message = "選んだフォルダの中に notes/ と index.json を作り、今あるメモをすべて移します。"
        open.prompt = "ここに移す"
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.canCreateDirectories = true
        open.directoryURL = store.rootURL.deletingLastPathComponent()
        guard open.runModal() == .OK, let dest = open.url else { return }

        let confirm = NSAlert()
        confirm.messageText = "\(store.memos.count)件のメモを移しますか？"
        confirm.informativeText = "移動先：\(dest.path)\n\n移し終わったら、元の場所のメモは消えます。"
        confirm.addButton(withTitle: "移す")
        confirm.addButton(withTitle: "キャンセル")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            try store.changeRoot(to: dest)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "保存先を変えられませんでした"
            alert.informativeText = error.localizedDescription + "\n元の場所のメモはそのまま残っています。"
            alert.runModal()
        }
    }

    @objc func toggleEdit() {
        NotificationCenter.default.post(name: .toggleEditMode, object: nil)
    }

    /// 一覧を前に出すたびに、ほかのエディタでの変更を読み直す
    func windowDidBecomeKey(_ notification: Notification) {
        store.reload()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // Dock に出さずメニューバーに常駐
    app.run()
}
