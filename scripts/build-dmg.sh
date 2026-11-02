#!/bin/zsh
# build/RemoteInput.app から配布用の build/RemoteInput.dmg を作る
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh
IDENTITY="${CODESIGN_IDENTITY:-Remote Input}"
STAGE="$(mktemp -d)"
trap '/bin/rm -rf "$STAGE"' EXIT
cp -R build/RemoteInput.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
/bin/rm -f build/RemoteInput.dmg
hdiutil create -volname "Remote Input" -srcfolder "$STAGE" -format UDZO -ov build/RemoteInput.dmg
codesign --force --sign "$IDENTITY" build/RemoteInput.dmg
echo build/RemoteInput.dmg
