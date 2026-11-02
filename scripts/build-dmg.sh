#!/bin/zsh
# build/FireRemote.app から配布用の build/FireRemote.dmg を作る
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh
IDENTITY="${CODESIGN_IDENTITY:-FireRemote Local}"
STAGE="$(mktemp -d)"
trap '/bin/rm -rf "$STAGE"' EXIT
cp -R build/FireRemote.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
/bin/rm -f build/FireRemote.dmg
hdiutil create -volname "Fire Remote" -srcfolder "$STAGE" -format UDZO -ov build/FireRemote.dmg
codesign --force --sign "$IDENTITY" build/FireRemote.dmg
echo build/FireRemote.dmg
