#!/bin/zsh
# Regenerate the Xcode project and build a Release app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -project OneScreen.xcodeproj -scheme OneScreen -configuration Release -derivedDataPath build -quiet
echo "Built: $PWD/build/Build/Products/Release/OneScreen.app"
