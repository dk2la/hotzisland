#!/bin/bash
# Build, test and launch HotzIsland. See ./run.sh --help.
set -euo pipefail
cd "$(dirname "$0")"

usage() {
    cat <<'HELP'
Usage: ./run.sh [options]

Build
  -b, --build        regenerate the Xcode project and build before launching
  -c, --clean        wipe the build folder first (implies --build)
  -r, --release      use the Release configuration (default: Debug)
  -t, --test         run the unit tests (implies --build)
  -v, --verbose      show the full xcodebuild output

Launch
  -d, --demo         sample data in every module
  -s, --settings     open the settings island at launch
  -o, --onboarding   show the first-launch onboarding again
  -n, --no-run       build / test only, do not launch
  -l, --logs         stream the app's logs after launching (Ctrl-C to stop)

Other
  -k, --stop         quit the running app and exit
  -h, --help         this text

Without --build the app is built only if no build exists yet.

Examples
  ./run.sh                     launch the last build
  ./run.sh -b -d -s            rebuild, launch with demo data and settings open
  ./run.sh -t -n               build and test, do not launch
  ./run.sh -c -r               clean Release build, then launch
HELP
}

build=0; clean=0; test=0; run=1; logs=0; verbose=0; config=Debug; app_args=()
for arg in "$@"; do
    case "$arg" in
        -b|--build) build=1 ;;
        -c|--clean) clean=1; build=1 ;;
        -r|--release) config=Release ;;
        -t|--test) test=1; build=1 ;;
        -v|--verbose) verbose=1 ;;
        -d|--demo) app_args+=(--demo) ;;
        -s|--settings) app_args+=(--settings) ;;
        -o|--onboarding) app_args+=(--onboarding) ;;
        -n|--no-run) run=0 ;;
        -l|--logs) logs=1 ;;
        -k|--stop) pkill -x HotzIsland 2>/dev/null && echo "stopped" || echo "not running"; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $arg" >&2; echo "try ./run.sh --help" >&2; exit 2 ;;
    esac
done

app="build/Build/Products/$config/HotzIsland.app"

# Runs xcodebuild; quiet mode keeps errors, warnings and the verdict only.
xcb() {
    local status=0
    if [[ $verbose == 1 ]]; then
        xcodebuild -project HotzIsland.xcodeproj -scheme HotzIsland \
            -configuration "$config" -derivedDataPath build "$@" || status=$?
    else
        xcodebuild -project HotzIsland.xcodeproj -scheme HotzIsland \
            -configuration "$config" -derivedDataPath build "$@" 2>&1 \
            | grep -E "error:|warning: [^M]|Executed [0-9]+ tests|\*\* " || true
        status=${PIPESTATUS[0]}
    fi
    [[ $status == 0 ]] || { echo "xcodebuild $* failed" >&2; exit "$status"; }
}

if [[ $clean == 1 ]]; then
    echo "==> clean"
    rm -rf build
fi
if [[ $build == 1 || ( $run == 1 && ! -d "$app" ) ]]; then
    command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }
    echo "==> build ($config)"
    xcodegen generate >/dev/null
    xcb build
fi
if [[ $test == 1 ]]; then
    echo "==> test"
    xcb test
fi
[[ $run == 1 ]] || exit 0

pkill -x HotzIsland 2>/dev/null && sleep 0.5 || true
echo "==> launch ${app_args[*]-}"
open "$app" --args ${app_args[@]+"${app_args[@]}"}

if [[ $logs == 1 ]]; then
    echo "==> logs (Ctrl-C to stop)"
    log stream --style compact --predicate 'subsystem == "com.dk2la.hotzisland"'
fi
