#!/usr/bin/env bash
# Build a local WakeAlarm.app (no App Store account required).
# Usage:
#   ./build.sh              # native arch (arm64 or x86_64)
#   ./build.sh --universal  # arm64 + x86_64 (needs both SDKs / lipo)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="WakeAlarm"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
MIN_OS="13.0"
UNIVERSAL=0

for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    -h|--help)
      echo "Usage: $0 [--universal]"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  echo "error: missing Resources/AppIcon.icns" >&2
  exit 1
fi
if [[ ! -f "$ROOT/Resources/Info.plist" ]]; then
  echo "error: missing Resources/Info.plist" >&2
  exit 1
fi

compile_one() {
  local arch="$1"
  local out="$2"
  local target="${arch}-apple-macosx${MIN_OS}"
  echo "  compiling $target …"
  swiftc \
    -O \
    -parse-as-library \
    -target "$target" \
    -sdk "$SDK" \
    -framework SwiftUI \
    -framework AppKit \
    -framework AVFoundation \
    -framework IOKit \
    -o "$out" \
    "$ROOT"/Sources/*.swift
}

echo "Building $APP_NAME …"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

if [[ "$UNIVERSAL" -eq 1 ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  compile_one "arm64" "$TMP/WakeAlarm-arm64"
  compile_one "x86_64" "$TMP/WakeAlarm-x86_64"
  lipo -create -output "$MACOS_DIR/$APP_NAME" "$TMP/WakeAlarm-arm64" "$TMP/WakeAlarm-x86_64"
else
  ARCH="$(uname -m)"
  compile_one "$ARCH" "$MACOS_DIR/$APP_NAME"
fi

cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

mkdir -p "$RESOURCES_DIR/Fonts"
cp "$ROOT/Resources/Fonts/"*.ttf "$RESOURCES_DIR/Fonts/"
cp "$ROOT/Resources/Fonts/"*LICENSE* "$RESOURCES_DIR/Fonts/" 2>/dev/null || true

# Ad-hoc sign so Gatekeeper is happier on first launch (still local / unsigned for App Store).
codesign --force --deep --sign - "$APP_DIR"

echo "Built: $APP_DIR"
file "$MACOS_DIR/$APP_NAME"
echo "Run with: open \"$APP_DIR\""
