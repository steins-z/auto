#!/usr/bin/env bash
set -euo pipefail

# Build SnapClip as a macOS .app bundle.
# Requires Xcode / Swift toolchain with macOS 14+ SDK.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build"
APP_NAME="SnapClip"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

cd "$ROOT"
swift build -c release --arch arm64 --arch x86_64

BIN_PATH="$(swift build -c release --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Sources/SnapClip/SnapClip-Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Ad-hoc sign for local development.
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
echo "Run with: open '$APP_BUNDLE'"
