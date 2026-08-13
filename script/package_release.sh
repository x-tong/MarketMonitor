#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MarketMonitor"
BUNDLE_ID="com.marketmonitor.app"
MIN_SYSTEM_VERSION="13.0"
DEFAULT_VERSION="0.2.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-${MARKET_MONITOR_VERSION:-$DEFAULT_VERSION}}"
OUTPUT_DIR="$ROOT_DIR/dist/releases"
STAGE_DIR="$OUTPUT_DIR/stage"
APP_BUNDLE="$STAGE_DIR/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.dmg"
ZIP_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.zip"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
    echo "invalid version: $VERSION (expected e.g. 0.2.0)" >&2
    exit 2
fi

cd "$ROOT_DIR"
./script/check.sh
swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$STAGE_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$OUTPUT_DIR"
cp "$BUILD_BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# No Developer ID certificate is required for this release path. Gatekeeper will
# show the expected first-launch warning because the app is not notarized.
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

rm -f "$DMG_PATH" "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"
hdiutil verify "$DMG_PATH"

echo "Release artifacts:"
echo "  $DMG_PATH"
echo "  $ZIP_PATH"
