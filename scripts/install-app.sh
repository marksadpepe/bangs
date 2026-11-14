#!/bin/bash
# Собирает Bangs и ставит в ~/Applications (без sudo), затем перезапускает.
# Автозапуск (SMAppService) запоминает путь к бандлу, поэтому запускать стоит именно установленную копию.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh release >/dev/null
dest="$HOME/Applications/Bangs.app"
mkdir -p "$HOME/Applications"
pkill -x Bangs 2>/dev/null || true
rm -rf "$dest"
cp -R build/Bangs.app "$dest"
open "$dest"
echo "✓ $dest"
