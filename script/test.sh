#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DEVELOPER_ROOT="$(xcode-select -p)"

if [[ "$DEVELOPER_ROOT" == */CommandLineTools ]]; then
  FRAMEWORK_DIR="$DEVELOPER_ROOT/Library/Developer/Frameworks"
  LIBRARY_DIR="$DEVELOPER_ROOT/Library/Developer/usr/lib"

  swift test \
    -Xswiftc -F -Xswiftc "$FRAMEWORK_DIR" \
    -Xlinker -F -Xlinker "$FRAMEWORK_DIR" \
    -Xlinker -rpath -Xlinker "$FRAMEWORK_DIR" \
    -Xlinker -rpath -Xlinker "$LIBRARY_DIR"
else
  swift test
fi
