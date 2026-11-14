#!/bin/bash
# Запуск тестов (Swift Testing). С одними Command Line Tools SwiftPM не находит Testing.framework,
# поэтому передаём путь к нему компилятору и линковщику. С полным Xcode хватает обычного `swift test`.
# Аргументы пробрасываются в `swift test`, например: scripts/test.sh --filter EventStateMachine
set -euo pipefail
cd "$(dirname "$0")/.."

dev="$(xcode-select -p)"
frameworks="$dev/Library/Developer/Frameworks"
[ -d "$frameworks" ] || frameworks="$dev/Platforms/MacOSX.platform/Developer/Library/Frameworks"
interop="$dev/Library/Developer/usr/lib"

exec swift test \
    -Xswiftc -F -Xswiftc "$frameworks" \
    -Xlinker -F -Xlinker "$frameworks" \
    -Xlinker -rpath -Xlinker "$frameworks" \
    -Xlinker -rpath -Xlinker "$interop" \
    "$@"
