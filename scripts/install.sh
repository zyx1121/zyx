#!/bin/sh
# Builds, signs, notarizes and copies zyx.app to /Applications, then opens it.
set -eu
cd "$(dirname "$0")/.."
scripts/bundle.sh
scripts/sign.sh .build/dist/zyx.app
scripts/notarize.sh .build/dist/zyx.app
pkill -f "zyx.app/Contents/MacOS/Zyx" || true
rm -rf /Applications/zyx.app
ditto .build/dist/zyx.app /Applications/zyx.app
open /Applications/zyx.app
