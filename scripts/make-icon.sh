#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -swift-version 5 -parse-as-library -target arm64-apple-macosx14.0 scripts/icon/MakeIcon.swift -o build/make-icon
rm -rf build/AppIcon.iconset
build/make-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
