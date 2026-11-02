#!/bin/zsh
# メニューバーアプリを build/FireRemote.app にまとめる(libopus を同梱し、アドホック署名する)
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product FireRemoteApp
BIN="$(swift build -c release --show-bin-path)/FireRemoteApp"
APP=build/FireRemote.app
OPUS=/opt/homebrew/opt/opus/lib/libopus.0.dylib
/bin/rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/FireRemote"
cp -L "$OPUS" "$APP/Contents/Frameworks/"
chmod u+w "$APP"/Contents/MacOS/* "$APP"/Contents/Frameworks/*
install_name_tool -id @rpath/libopus.0.dylib "$APP/Contents/Frameworks/libopus.0.dylib" 2>/dev/null
install_name_tool -change "$OPUS" @executable_path/../Frameworks/libopus.0.dylib "$APP/Contents/MacOS/FireRemote" 2>/dev/null
cat > "$APP/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.firetvremote.app</string>
<key>CFBundleExecutable</key><string>FireRemote</string>
<key>CFBundleName</key><string>Fire Remote</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
# 開発用証明書があれば使う。署名が変わらないため、再ビルドしても権限が外れにくい
IDENTITY="${CODESIGN_IDENTITY:-$(/usr/bin/security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
echo "署名: $IDENTITY"
codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/libopus.0.dylib"
codesign --force --sign "$IDENTITY" "$APP"
echo "$APP"
