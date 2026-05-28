#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
"$ROOT/install-autostart.sh"

echo
echo "Codex Usage Float auto-start has been installed."
echo "You can close this window."
read -r -p "Press Return to close..."
