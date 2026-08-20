#!/bin/bash
set -euo pipefail
# 首次运行需下载 iOS 运行时（约数 GB，只执行一次）
if ! xcrun simctl list runtimes | grep -q "iOS"; then
  xcodebuild -downloadPlatform iOS
fi
if ! xcrun simctl list devices available | grep -q "iPhone 16 ("; then
  DEVICE_TYPE=$(xcrun simctl list devicetypes | grep -oE 'com.apple.CoreSimulator.SimDeviceType.iPhone-16([^ )]*)' | head -1)
  RUNTIME_ID=$(xcrun simctl list runtimes | grep -oE 'com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]+' | tail -1)
  xcrun simctl create "iPhone 16" "$DEVICE_TYPE" "$RUNTIME_ID"
fi
echo "simulator ready: $(xcrun simctl list devices available | grep 'iPhone 16 (' | head -1)"
