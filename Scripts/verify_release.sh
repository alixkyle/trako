#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/.build/release/Trako.app}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle: $APP_PATH" >&2
  exit 1
fi

echo "Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Checking sandbox entitlement..."
if ! codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -q "com.apple.security.app-sandbox"; then
  echo "Missing sandbox entitlement" >&2
  exit 1
fi

echo "Checking Info.plist..."
plutil -lint "$APP_PATH/Contents/Info.plist"

echo "Checking icon..."
icon_name="$(plutil -extract CFBundleIconFile raw "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
if [[ -z "$icon_name" ]]; then
  icon_name="$(plutil -extract CFBundleIconName raw "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
fi
if [[ -z "$icon_name" || ! -f "$APP_PATH/Contents/Resources/${icon_name%.icns}.icns" ]]; then
  echo "Missing icon resource declared by Info.plist" >&2
  exit 1
fi

echo "Release verification passed: $APP_PATH"
