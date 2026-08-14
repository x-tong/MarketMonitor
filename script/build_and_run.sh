#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MarketMonitor"
BUNDLE_ID="com.example.MarketMonitor"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

stop_running_app() {
  if ! pgrep -x "$APP_NAME" >/dev/null; then
    return
  fi

  pkill -TERM -x "$APP_NAME" >/dev/null 2>&1 || true
  for _ in {1..50}; do
    if ! pgrep -x "$APP_NAME" >/dev/null; then
      return
    fi
    sleep 0.1
  done

  pkill -KILL -x "$APP_NAME" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if ! pgrep -x "$APP_NAME" >/dev/null; then
      return
    fi
    sleep 0.1
  done

  echo "failed to stop existing $APP_NAME process" >&2
  exit 1
}

wait_for_single_instance() {
  local process_count
  local process_ids
  for _ in {1..50}; do
    process_ids="$(pgrep -x "$APP_NAME" 2>/dev/null || true)"
    if [[ -z "$process_ids" ]]; then
      process_count=0
    else
      process_count="$(wc -l <<<"$process_ids" | tr -d ' ')"
    fi
    if [[ "$process_count" == "1" ]]; then
      return
    fi
    if [[ "$process_count" -gt 1 ]]; then
      echo "expected one $APP_NAME process, found $process_count" >&2
      stop_running_app
      exit 1
    fi
    sleep 0.1
  done

  echo "$APP_NAME did not start within 5 seconds" >&2
  exit 1
}

stop_running_app
swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() { /usr/bin/open -n "$APP_BUNDLE"; }

case "$MODE" in
  run) open_app ;;
  --debug|debug) lldb -- "$APP_BINARY" ;;
  --logs|logs) open_app; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry|telemetry) open_app; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --verify|verify) open_app; wait_for_single_instance ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
