#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
APP_DIR="$PROJECT_DIR/build/HingeScape.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
# Info.plist is the single source of truth for the minimum macOS version.
MIN_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PROJECT_DIR/Info.plist")"

mkdir -p "$MACOS_DIR"
mkdir -p "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/Assets/HingeScape.icns" "$CONTENTS_DIR/Resources/"
cp "$PROJECT_DIR/Assets/HingeScape.png" "$CONTENTS_DIR/Resources/"
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

swiftc \
  -parse-as-library \
  -O \
  -target "$(uname -m)-apple-macos$MIN_MACOS" \
  -framework SwiftUI \
  -framework AppKit \
  -framework IOKit \
  -framework QuartzCore \
  -framework MetalKit \
  -framework ScreenCaptureKit \
  -framework Carbon \
  -framework Security \
  -o "$MACOS_DIR/HingeScape" \
  "$PROJECT_DIR"/Sources/*.swift

# Hardened Runtime: injected libraries can't borrow the Screen Recording grant.
codesign --force --options runtime --sign - "$APP_DIR"
echo "Built: $APP_DIR"
