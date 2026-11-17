#!/bin/bash
# Builds MicLid.app and installs it in an Applications folder.
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/build-app.sh release

DEST="/Applications"
if [ ! -w "$DEST" ]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi

pkill -x MicLid 2>/dev/null || true
rm -rf "$DEST/MicLid.app"
ditto build/MicLid.app "$DEST/MicLid.app"

echo "installed $DEST/MicLid.app"
open "$DEST/MicLid.app" 2>/dev/null || { sleep 1; open "$DEST/MicLid.app"; }
