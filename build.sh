#!/bin/zsh
# リリースビルドして IdeaMemo.app を作る
#   ./build.sh            リポジトリの中に IdeaMemo.app を作る
#   ./build.sh --install  さらに /Applications に入れ替えて起動し直す
set -e
cd "$(dirname "$0")"
swift build -c release
APP=IdeaMemo.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS
cp .build/release/IdeaMemo $APP/Contents/MacOS/
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>IdeaMemo</string>
  <key>CFBundleIdentifier</key><string>dev.yuta.ideamemo</string>
  <key>CFBundleExecutable</key><string>IdeaMemo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - $APP
echo "built: $(pwd)/$APP"

if [[ "$1" == "--install" ]]; then
  DEST=/Applications/$APP
  # 動いているアプリ（リポジトリの中のものも含む）を終了させてから入れ替える
  pkill -f "$APP/Contents/MacOS/IdeaMemo" && sleep 1 || true
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  open "$DEST"
  echo "installed: $DEST"
fi
