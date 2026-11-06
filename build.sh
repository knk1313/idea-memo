#!/bin/zsh
# リリースビルドして IdeaMemo.app を作る
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
