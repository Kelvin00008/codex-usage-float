#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_EXEC="$ROOT/CodexUsageFloat.app/Contents/MacOS/UsageFloat"
BUILD="$ROOT/build.sh"
LOG="/tmp/codex-usage-float-monitor.log"

if [[ ! -x "$APP_EXEC" ]]; then
  "$BUILD" >>"$LOG" 2>&1 || exit 1
fi

while true; do
  if /usr/bin/pgrep -x "Codex" >/dev/null 2>&1; then
    if ! /usr/bin/pgrep -f "$APP_EXEC" >/dev/null 2>&1; then
      /usr/bin/nohup "$APP_EXEC" >/tmp/codex-usage-float.out 2>/tmp/codex-usage-float.err &
    fi
  else
    /usr/bin/pkill -f "$APP_EXEC" >/dev/null 2>&1 || true
  fi

  /bin/sleep 10
done
