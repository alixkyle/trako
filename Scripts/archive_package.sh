#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_PATH="${1:-$ROOT_DIR/.build/archive/Trako.xcarchive}"

cd "$ROOT_DIR"
rm -rf "$ARCHIVE_PATH"

xcodebuild \
  -project Trako/Trako.xcodeproj \
  -scheme Trako \
  -destination 'generic/platform=macOS' \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive

echo "$ARCHIVE_PATH"
