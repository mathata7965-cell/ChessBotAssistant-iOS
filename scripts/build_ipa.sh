#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> 清理舊建置產物..."
rm -rf build ChessBotAssistant.ipa

if command -v xcodegen >/dev/null 2>&1; then
  echo "==> 使用 XcodeGen 產生 ChessBotAssistant.xcodeproj..."
  xcodegen generate
fi

echo "==> 使用 xcodebuild 編譯 Release iOS App (Sideload Ad-Hoc)..."
xcodebuild clean build \
  -project ChessBotAssistant.xcodeproj \
  -target ChessBotAssistant \
  -configuration Release \
  -sdk iphoneos \
  SYMROOT="$ROOT_DIR/build" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES

echo "==> 套用 Ad-Hoc 簽章並打包 Payload 為 ChessBotAssistant.ipa..."
mkdir -p build/ipa/Payload
cp -R build/Release-iphoneos/ChessBotAssistant.app build/ipa/Payload/
codesign --force --deep --sign - build/ipa/Payload/ChessBotAssistant.app
(cd build/ipa && zip -r "$ROOT_DIR/ChessBotAssistant.ipa" Payload)

echo "==> 打包完成：$ROOT_DIR/ChessBotAssistant.ipa"
ls -lh "$ROOT_DIR/ChessBotAssistant.ipa"
