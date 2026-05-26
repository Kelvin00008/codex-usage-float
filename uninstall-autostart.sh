#!/usr/bin/env bash
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/local.codex.usagefloat.monitor.plist"

launchctl unload "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"
pkill -f "CodexUsageFloat.app/Contents/MacOS/UsageFloat" >/dev/null 2>&1 || true
pkill -f "monitor-codex.sh" >/dev/null 2>&1 || true
