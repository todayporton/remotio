#!/bin/zsh
# 仮想マイクのドライバを build/RemotioMicrophone.driver にまとめる
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=build/RemotioMicrophone.driver
OBJ=.build/driver-obj
IDENTITY="${CODESIGN_IDENTITY:-todayporton}"
mkdir -p "$OBJ"
for src in Driver/RemotioMicrophone.cpp Vendor/libASPL/src/*.cpp; do
  obj="$OBJ/$(basename "$src" .cpp).o"
  if [[ ! -f "$obj" || "$src" -nt "$obj" ]]; then
    clang++ -std=c++17 -O2 -arch arm64 -mmacosx-version-min=13.0 \
      -IVendor/libASPL/include -IVendor/libASPL/src -c "$src" -o "$obj"
  fi
done
/bin/rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"
cp Driver/Info.plist "$OUT/Contents/Info.plist"
clang++ -bundle -arch arm64 -mmacosx-version-min=13.0 "$OBJ"/*.o \
  -framework CoreFoundation -framework CoreAudio \
  -o "$OUT/Contents/MacOS/RemotioMicrophone"
codesign --force --sign "$IDENTITY" "$OUT"
echo "$OUT"
