#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Trako"
CONFIGURATION="release"
BUILD_DIR="$ROOT_DIR/.build/$CONFIGURATION"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ENTITLEMENTS="$ROOT_DIR/Config/Trako.local.entitlements"
ICON="$ROOT_DIR/Resources/Trako.icns"
PRIVACY_MANIFEST="$ROOT_DIR/Trako/Trako/PrivacyInfo.xcprivacy"

cd "$ROOT_DIR"
if [[ ! -f "$ICON" ]]; then
  swift Scripts/make_icon.swift
fi

swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ICON" "$RESOURCES_DIR/Trako.icns"
if [[ -f "$PRIVACY_MANIFEST" ]]; then
  cp "$PRIVACY_MANIFEST" "$RESOURCES_DIR/PrivacyInfo.xcprivacy"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.alixkyle.trako</string>
  <key>CFBundleIconFile</key>
  <string>Trako</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Created locally.</string>
</dict>
</plist>
PLIST

# Local builds omit App Sandbox so stats stay in ~/Library/Application Support/Trako.
# App Store archives should use Config/Trako.entitlements via Xcode instead.
codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP_DIR"

echo "$APP_DIR"
