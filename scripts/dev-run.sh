#!/bin/sh
# Builds, signs and restarts zyx. Extra environment passes through, e.g.
#   ZYX_OPEN_MENU=1 scripts/dev-run.sh
set -eu
cd "$(dirname "$0")/.."
scripts/bundle.sh
app=.build/dist/zyx.app
scripts/sign.sh "$app"
pkill -f "zyx.app/Contents/MacOS/Zyx" || true
"$app/Contents/MacOS/Zyx" >/dev/null 2>&1 &
