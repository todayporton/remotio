#!/bin/zsh
# build/Remotio.app から配布用の build/Remotio.dmg を作る
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh
IDENTITY="${CODESIGN_IDENTITY:-todayporton}"
STAGE="$(mktemp -d)"
trap '/bin/rm -rf "$STAGE"' EXIT
cp -R build/Remotio.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
/bin/rm -f build/Remotio.dmg
hdiutil create -volname "Remotio" -srcfolder "$STAGE" -format UDZO -ov build/Remotio.dmg
codesign --force --sign "$IDENTITY" build/Remotio.dmg
echo build/Remotio.dmg
