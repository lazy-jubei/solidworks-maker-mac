#!/bin/zsh
# Called after the SolidWorks installer and its Wine server have stopped.
set -eu
source "${0:A:h}/env.sh"
manager="$ROOT/scripts/tools/intel-renderer.py"
server="$WINE_APP/Contents/Resources/wine/bin/wineserver"
setting="${SW_INTEL_ENHANCED_GRAPHICS:-auto}"
supported=0
if [[ "$setting" != 0 ]] && (( ! SW_HOST_ARM64 )); then
    macos_major="$(sw_vers -productVersion | cut -d. -f1)"
    if (( macos_major >= 15 )); then
        device=$(xcrun swift -e 'import Metal; print(MTLCreateSystemDefaultDevice()?.name ?? "")' 2>/dev/null) || device=
        if [[ "$device" == AMD\ Radeon* ]]; then supported=1; fi
    fi
fi
if (( ! supported )); then
    if [[ "$setting" == 1 ]]; then
        print -u2 'Enhanced Graphics requires an Intel Mac with an AMD Radeon default Metal device and macOS 15 or newer.'
        exit 2
    fi
    if [[ -d "$WINEPREFIX/.sw-intel-renderer" ]]; then
        python3 "$ROOT/scripts/tools/require-stopped.py" "$server"
        trap '"$server" -k 2>/dev/null || true; "$server" -w 2>/dev/null || true' EXIT
        python3 "$manager" disable
    fi
    exit 0
fi
python3 "$ROOT/scripts/tools/require-stopped.py" "$server"
build="${SW_BUILD:-$VOL/build}"
key=$(cat "$ROOT/scripts/build-intel-renderer.sh" "$ROOT"/scripts/patches/winemetalgl-*.patch | shasum -a 256 | cut -d ' ' -f 1)
artifact="$build/intel-renderer-$key"
if [[ ! -d "$artifact/wine-module" ]]; then
    source "$ROOT/scripts/tools/macports.sh"
    if ! command -v cmake >/dev/null || ! command -v ninja >/dev/null; then
        macports_install cmake ninja
    fi
    "$ROOT/scripts/build-intel-renderer.sh" "$build/src-wine-$WINE_VERSION" "$build/llvm-mingw/bin" "$artifact"
fi
# Building the renderer can take several minutes. Check again before touching the prefix.
python3 "$ROOT/scripts/tools/require-stopped.py" "$server"
trap '"$server" -k 2>/dev/null || true; "$server" -w 2>/dev/null || true' EXIT
python3 "$manager" enable "$artifact/wine-module"
