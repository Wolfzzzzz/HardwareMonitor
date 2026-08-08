#!/bin/bash
# 一键构建硬件监控 App（无需打开 Xcode）
set -e
cd "$(dirname "$0")"

echo "==> 开始构建 HardwareMonitor ..."
xcodebuild -project HardwareMonitor.xcodeproj \
           -scheme HardwareMonitor \
           -configuration Debug \
           -derivedDataPath build \
           CODE_SIGNING_ALLOWED=NO \
           build 2>&1 | tail -25

APP="build/Build/Products/Debug/HardwareMonitor.app"
if [ -d "$APP" ]; then
  echo ""
  echo "✅ 构建成功：$APP"
  echo "   运行：open \"$APP\""
else
  echo "❌ 构建失败，请查看上方日志"
  exit 1
fi
