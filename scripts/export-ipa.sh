#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
rm -rf build/LightCal.xcarchive build/Payload build/LightCal.ipa
xcodebuild -project LightCal.xcodeproj -scheme LightCal -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/LightCal.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive

APP_DIR=$(find build/LightCal.xcarchive/Products/Applications -maxdepth 1 -name "*.app" | head -1)
mkdir -p build/Payload
cp -R "$APP_DIR" build/Payload/
(cd build && zip -rq LightCal.ipa Payload)
rm -rf build/Payload
echo "✅ IPA 已生成: build/LightCal.ipa"
