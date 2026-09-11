#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
OUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUT_DIR"' EXIT

# Built with -O on purpose: the checks must hold in optimized builds too.
swiftc \
  -parse-as-library \
  -O \
  -o "$OUT_DIR/tests" \
  "$PROJECT_DIR/Sources/ScreenCapturePermissionPreparation.swift" \
  "$PROJECT_DIR/Sources/CaptureSafety.swift" \
  "$PROJECT_DIR/Tests/PermissionPreparationTests.swift"
"$OUT_DIR/tests"
