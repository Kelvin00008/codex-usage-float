#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/local.codex.usagefloat.monitor.plist"
SCRIPT="$ROOT/monitor-codex.sh"

chmod +x "$SCRIPT" "$ROOT/Launch Codex Usage Float.command" "$ROOT/build.sh"
"$ROOT/build.sh" >/dev/null
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.codex.usagefloat.monitor</string>
  <key>ProgramArguments</key>
  <array>
    <string>$SCRIPT</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/codex-usage-float-monitor.out</string>
  <key>StandardErrorPath</key>
  <string>/tmp/codex-usage-float-monitor.err</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST" >/dev/null 2>&1 || true
launchctl load "$PLIST"
echo "$PLIST"
