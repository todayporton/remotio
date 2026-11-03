#!/bin/zsh
# メニューバーアプリを build/Remotio.app にまとめる(libopus を同梱し、アドホック署名する)
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product RemotioApp
scripts/build-driver.sh
BIN="$(swift build -c release --show-bin-path)/RemotioApp"
APP=build/Remotio.app
OPUS=/opt/homebrew/opt/opus/lib/libopus.0.dylib
/bin/rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp /opt/homebrew/opt/opus/COPYING "$APP/Contents/Resources/libopus-COPYING.txt"
cp Vendor/libASPL/LICENSE "$APP/Contents/Resources/libASPL-LICENSE.txt"
cp -R build/RemotioMicrophone.driver "$APP/Contents/Resources/"
cp Assets/AppIcon.icns "$APP/Contents/Resources/"
# 翻訳ファイル(英語と日本語)
cp -R Resources/Localization/en.lproj Resources/Localization/ja.lproj "$APP/Contents/Resources/"
cp "$BIN" "$APP/Contents/MacOS/Remotio"
cp -L "$OPUS" "$APP/Contents/Frameworks/"
chmod u+w "$APP"/Contents/MacOS/* "$APP"/Contents/Frameworks/*
install_name_tool -id @rpath/libopus.0.dylib "$APP/Contents/Frameworks/libopus.0.dylib" 2>/dev/null
install_name_tool -change "$OPUS" @executable_path/../Frameworks/libopus.0.dylib "$APP/Contents/MacOS/Remotio" 2>/dev/null
cat > "$APP/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>online.todayporton.remotio</string>
<key>CFBundleExecutable</key><string>Remotio</string>
<key>CFBundleName</key><string>Remotio</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>ja</string></array>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
# 配布物の署名を変えないよう、証明書は固定する(権限はこの署名に結びつく)
IDENTITY="${CODESIGN_IDENTITY:-todayporton}"
echo "署名: $IDENTITY"
codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/libopus.0.dylib"
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
