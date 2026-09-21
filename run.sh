#!/bin/bash
# Launches HotzIsland. Usage: ./run.sh [--build] [--test] [app args...]
#   --build   regenerate the Xcode project and build before launching
#   --test    run the unit tests (implies --build), then launch
# Anything else is passed to the app: --demo --settings --onboarding
set -euo pipefail
cd "$(dirname "$0")"

build=0; test=0; args=()
for arg in "$@"; do
    case "$arg" in
        --build) build=1 ;;
        --test) build=1; test=1 ;;
        *) args+=("$arg") ;;
    esac
done

app="build/Build/Products/Debug/HotzIsland.app"
xcb() { xcodebuild -project HotzIsland.xcodeproj -scheme HotzIsland -derivedDataPath build "$@" | grep -E "error:|warning: [^M]|\*\* " || true; }

if [[ $build == 1 || ! -d "$app" ]]; then
    xcodegen generate >/dev/null
    xcb build
fi
[[ $test == 1 ]] && xcb test

pkill -x HotzIsland 2>/dev/null && sleep 0.5 || true
open "$app" --args ${args[@]+"${args[@]}"}
