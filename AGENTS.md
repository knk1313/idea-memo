# AGENTS.md

このファイルは、このリポジトリで動くAIコーディングエージェント（Claude Code、OpenAI Codexなど）が共通で参照する**禁止事項と最低限のチェック**を集めた索引である。

- **Claude Code**：ルートの`CLAUDE.md`が`@AGENTS.md`で取り込む
- **OpenAI Codex**：ルートの`AGENTS.md`を直接読み込む

本ファイルは、AIが**コードを書く・直す・出す**ときに踏み外してはいけない事項に絞る。

## プロジェクト概要

`README.md`を参照（技術スタック・ディレクトリ構成）。

## コマンド

実行する場所は、すべてリポジトリのルート。

| 用途 | コマンド |
| --- | --- |
| ビルド（型の検査を含む） | `swift build` |
| アプリ（`IdeaMemo.app`）を作る | `./build.sh` |
| 起動 | `open IdeaMemo.app` |
| `/Applications`に入れ替えて起動し直す | `./build.sh --install` |

動いているアプリを作り直すときは、先に`pkill -f IdeaMemo.app/Contents/MacOS/IdeaMemo`で終了させてから`./build.sh`を実行する。`--install`は終了から起動し直しまでをまとめて行う。利用者がふだん使っている`/Applications/IdeaMemo.app`を置き換えるので、頼まれたときだけ使う。

アプリはメモを利用者が選んだフォルダー（既定は`~/Documents/IdeaMemo`）に保存する。`memo/`はその保存先にした利用者のデータなので、読み書きしない。

## git操作

**gitを操作しない**。次の操作は、すべて人間が行う。人間が明示的に依頼したときだけ実行する。

- ブランチの作成・切り替え
- `add`、`commit`、`push`、`merge`、`rebase`、`reset`、`stash`
- PRの作成

コードの変更は、作業ツリーに残すところまでで止める。状態を確認する読み取り専用のコマンド（`git status`、`git log`、`git diff`など）は実行してよい。

## ドキュメントとコードの食い違い

**ドキュメントと既存のコードが食い違うときは、コードの書き方に従う**。READMEや注記の説明が古いまま残っていることがあるため、動いているコードを正とする。

見つけた食い違いは、その場で黙って直さず、作業の最後の返答ですべて挙げる。ドキュメントを直すかどうかは、人間が決める。

## 規約

- **コミットメッセージ**：日本語。1行目に`feat:`などの種別prefixを付ける（`feat`、`fix`、`refactor`、`perf`、`chore`、`docs`、`test`、`ci`）。
- **Issue**：タイトルに種別prefixを付ける。本文は`.github/ISSUE_TEMPLATE/`のテンプレート（`機能追加.md`か`バグ修正.md`）を選び、その見出し構成のまま全項目を埋める。調査タスクは`機能追加.md`を使う。
- **PR**：`.github/pull_request_template.md`の見出し構成のまま全項目を埋める。
- **コードのコメント・ドキュメント文字列**：日本語で書く。
