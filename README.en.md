# IdeaMemo

[日本語](README.md) | English

A menu bar memo app for macOS. Each memo is saved as its own Markdown file, so you can also read and edit your memos in any other editor.

![The IdeaMemo input panel and memo list](https://github.com/user-attachments/assets/30623fb9-f542-4bd5-8541-1bcc2616b883)

> The app's interface is in Japanese. This README gives the Japanese label along with an English translation, for example 「メモ一覧」 (Memo list).

## Features

- Open the input panel from anywhere with ⌃⌘Space
- Markdown you type in the input panel is styled as you write
- Each memo is saved as a separate Markdown file, and metadata such as creation time is kept in `index.json`
- Search, preview, edit, and delete memos in the memo list
- Change the storage folder, and existing memos move with it

## Requirements

- macOS 14 or later
- Swift 5.9 or later (included with Xcode or the Command Line Tools)

There are no external package dependencies.

## Build and run

Run the following from the repository root:

```bash
./build.sh
open IdeaMemo.app
```

`build.sh` makes a release build and creates `IdeaMemo.app`. Once it is running, a light bulb icon for IdeaMemo appears in the menu bar. The app does not appear in the Dock.

To rebuild while the app is running, quit it first:

```bash
pkill -f IdeaMemo.app/Contents/MacOS/IdeaMemo
./build.sh
open IdeaMemo.app
```

For everyday use, run with `--install`. This replaces `/Applications/IdeaMemo.app` with the new build and relaunches it. Use the same command again after changing the code.

```bash
./build.sh --install
```

To launch IdeaMemo automatically when you log in, add `/Applications/IdeaMemo.app` under System Settings → General → Login Items.

The app is signed ad hoc by `build.sh`. That is enough to run a build you made yourself, but it is not notarized, so a copy downloaded from elsewhere will be blocked by Gatekeeper.

## Usage

### Writing a memo

Press ⌃⌘Space to open the input panel. The following keys work in the panel:

| Key | Action |
| --- | --- |
| ⏎ | Save and close |
| ⌃⏎ or ⇧⏎ | Insert a line break |
| ⌘L | Open the memo list |
| esc | Close (unsaved text is kept for the next time you open the panel) |

Pressing ⏎ while a Japanese (or other) input method is composing text confirms the conversion and does not save. The panel grows downward as you add lines, and once it reaches the height of the screen, the text scrolls inside it.

### Writing Markdown in the input panel

In the input panel and in the memo list's editor, Markdown is styled as you type. The syntax characters stay visible but are shown in a lighter color.

- Headings: lines that start with `#`, `##`, or `###` followed by a space are shown larger and in bold
- Bold, italic, strikethrough, code, and links: `**bold**`, `*italic*`, `~~strikethrough~~`, `` `code` ``, and `[text](URL)` are styled accordingly
- Lists: pressing a line break on a line that starts with `-` or `1.` followed by a space starts the next line with the same marker. A line break on an empty item ends the list
- Checkboxes: typing `[]` and a space at the start of a line turns it into `- [ ]`
- Indentation: on a list line, Tab indents and ⇧Tab outdents

### Viewing, editing, and deleting memos

Open the memo list by choosing 「メモ一覧」 (Memo list) from the IdeaMemo icon in the menu bar, or by pressing ⌘L.

- Select a memo to see its Markdown preview. Clicking a checkbox also changes `[ ]` to `[x]` in the file
- Press ⌘E to switch between preview and editing. Edits are saved automatically
- Type in the search field to show only memos whose text contains that word
- Click the select button on each memo you want, then click 「削除」 (Delete) to delete them all at once. The Delete key works too
- Deleted memo files go to the Trash, so you can restore them from the Finder

### Changing the storage folder

Choose 「保存先を変更…」 (Change storage folder…) from the IdeaMemo icon in the menu bar, then pick a folder. You can also use 「変更…」 (Change…) at the bottom of the memo list's sidebar.

- All existing memos move to the new folder. Every file is copied before the originals are removed, so your memos stay in place if something fails partway
- If the new folder already contains IdeaMemo memos, the two sets are merged
- The default storage folder is `~/Documents/IdeaMemo`

## Stored files

The storage folder contains two things:

```text
storage-folder/
├── index.json
└── notes/
    ├── 2026-11-06-194747.md
    └── 2026-11-06-201530.md
```

- `notes/`: the memo text. Each memo is one Markdown file, named after the time it was created
- `index.json`: each memo's ID, file name, title, creation time, and last update time

If you edit or add files in `notes/` with another editor, IdeaMemo reloads them the next time you open the memo list.

## Tech stack and directory layout

IdeaMemo is written in Swift and SwiftUI, and uses AppKit for the menu bar and windows. The global shortcut that opens the input panel is registered with Carbon's `RegisterEventHotKey`, which does not require Accessibility permission.

```text
.
├── Package.swift
├── build.sh                  # Builds IdeaMemo.app
└── Sources/IdeaMemo/
    ├── main.swift            # App startup, menu bar item, menus, storage folder change
    ├── HotKey.swift          # Registers the global shortcut for the input panel
    ├── QuickPanel.swift      # The input panel shown in the center of the screen
    ├── MemoTextView.swift    # The text view (line breaks, list continuation, indentation)
    ├── MarkdownStyler.swift  # Styles Markdown as you type
    ├── MarkdownView.swift    # Preview in the memo list
    ├── ListView.swift        # The memo list
    └── Store.swift           # Reading and writing memos, moving the storage folder
```

## License

Released under the [MIT License](LICENSE). See [CONTRIBUTING.md](CONTRIBUTING.md) for bug reports and suggestions (written in Japanese), and [SECURITY.md](SECURITY.md) for reporting vulnerabilities.
