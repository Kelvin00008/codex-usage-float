#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/CodexUsageFloat.app"

if [[ ! -x "$APP/Contents/MacOS/UsageFloat" ]]; then
  "$ROOT/build.sh" >/dev/null
fi

nohup "$APP/Contents/MacOS/UsageFloat" >/tmp/codex-usage-float.out 2>/tmp/codex-usage-float.err &
