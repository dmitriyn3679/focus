#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/app.noindex/Focus.app
BIN=build/bin
rm -rf "$APP" "$BIN"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BIN"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target "$arch-apple-macosx14.0" \
    Sources/Core/*.swift Sources/App/*.swift -o "$BIN/Focus-$arch"
done
lipo -create "$BIN/Focus-arm64" "$BIN/Focus-x86_64" -output "$APP/Contents/MacOS/Focus"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"
