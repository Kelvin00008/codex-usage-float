#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/CodexUsageFloat.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
BUILD_DIR="$ROOT/.build"
MODULE_CACHE="$BUILD_DIR/module-cache"

rm -rf "$APP"
mkdir -p "$MACOS" "$CONTENTS/Resources" "$MODULE_CACHE"

swiftc "$ROOT/UsageFloat.swift" \
  -framework AppKit \
  -module-cache-path "$MODULE_CACHE" \
  -o "$MACOS/UsageFloat"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>UsageFloat</string>
  <key>CFBundleIdentifier</key>
  <string>local.codex.usagefloat</string>
  <key>CFBundleName</key>
  <string>Codex Usage Float</string>
  <key>CFBundleDisplayName</key>
  <string>Codex Usage Float</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.0</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "$APP"
