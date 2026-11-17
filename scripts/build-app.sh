#!/bin/bash
# Builds MicLid.app from the Swift package.
# Usage: ./scripts/build-app.sh [debug|release]
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="MicLid"
APP="build/$APP_NAME.app"

swift build -c "$CONFIG"

if [ ! -f Resources/AppIcon.icns ]; then
    swift scripts/make-icon.swift
fi

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with a real identity when one exists, otherwise ad-hoc. Both run fine;
# a real identity keeps Gatekeeper and Login Items happier.
IDENTITY="${MICLID_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk '/Apple Development|Developer ID Application/ { print $2; exit }')"
fi

if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" "$APP" >/dev/null
    echo "signed with: $IDENTITY"
else
    codesign --force --sign - "$APP" >/dev/null 2>&1 || true
    echo "signed ad-hoc"
fi

echo "built $APP"
