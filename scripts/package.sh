#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh
STAGE=build/package/Focus
rm -rf build/package build/Focus.zip
mkdir -p "$STAGE"
ditto build/app.noindex/Focus.app "$STAGE/Focus.app"
cp README.md "$STAGE/README.md"
ditto -c -k --keepParent "$STAGE" build/Focus.zip
echo "Packaged build/Focus.zip"
