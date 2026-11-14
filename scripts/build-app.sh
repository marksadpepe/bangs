#!/bin/bash
# Собирает build/Bangs.app без Xcode: swift build → бандл → подпись.
# Использование: scripts/build-app.sh [release|debug]
# SIGN_IDENTITY — имя сертификата для подписи (по умолчанию ad-hoc "-").
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG" --product Bangs
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/Bangs.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Bangs" "$APP/Contents/MacOS/Bangs"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP" >/dev/null
echo "$APP"
