#!/bin/zsh
# メニューバーアプリを build/RemoteInput.app にまとめる(libopus を同梱し、アドホック署名する)
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product RemoteInputApp
BIN="$(swift build -c release --show-bin-path)/RemoteInputApp"
APP=build/RemoteInput.app
OPUS=/opt/homebrew/opt/opus/lib/libopus.0.dylib
/bin/rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp /opt/homebrew/opt/opus/COPYING "$APP/Contents/Resources/libopus-COPYING.txt"
cp "$BIN" "$APP/Contents/MacOS/RemoteInput"
cp -L "$OPUS" "$APP/Contents/Frameworks/"
chmod u+w "$APP"/Contents/MacOS/* "$APP"/Contents/Frameworks/*
install_name_tool -id @rpath/libopus.0.dylib "$APP/Contents/Frameworks/libopus.0.dylib" 2>/dev/null
install_name_tool -change "$OPUS" @executable_path/../Frameworks/libopus.0.dylib "$APP/Contents/MacOS/RemoteInput" 2>/dev/null
cat > "$APP/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.potkc.remoteinput</string>
<key>CFBundleExecutable</key><string>RemoteInput</string>
<key>CFBundleName</key><string>Remote Input</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
# 配布物の署名を変えないよう、証明書は固定する(権限はこの署名に結びつく)
IDENTITY="${CODESIGN_IDENTITY:-RemoteInput}"
echo "署名: $IDENTITY"
codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/libopus.0.dylib"
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
