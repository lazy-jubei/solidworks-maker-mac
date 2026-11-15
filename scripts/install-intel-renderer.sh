#!/bin/zsh
# Called after the SolidWorks installer and its Wine server have stopped.
set -eu
source "${0:A:h}/env.sh"
manager="$ROOT/scripts/tools/intel-renderer.py"
if [[ "${SW_INTEL_ENHANCED_GRAPHICS:-0}" != 1 && ! -d "$WINEPREFIX/.sw-intel-renderer" ]]; then
    exit 0
fi
server="$WINE_APP/Contents/Resources/wine/bin/wineserver"
python3 "$ROOT/scripts/tools/require-stopped.py" "$server"
if [[ "${SW_INTEL_ENHANCED_GRAPHICS:-0}" != 1 ]]; then
    trap '"$server" -k 2>/dev/null || true; "$server" -w 2>/dev/null || true' EXIT
    python3 "$manager" disable
    exit 0
fi
if (( SW_HOST_ARM64 )); then
    print -u2 'The experimental Enhanced Graphics renderer is for Intel Macs.'
    exit 2
fi
macos_major="$(sw_vers -productVersion | cut -d. -f1)"
if (( macos_major < 15 )); then
    print -u2 'The experimental Enhanced Graphics renderer requires macOS 15 or newer.'
    exit 2
fi
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
