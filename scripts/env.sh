# Shared settings. Source this: `source scripts/env.sh`
# Resolve relative to this checkout, including when sourced from another directory.
ROOT="${SW_PROJECT_ROOT:-${${(%):-%x}:A:h:h}}"
SW_CONFIG_FILE="${SW_CONFIG_FILE:-$ROOT/config.local.zsh}"
if [[ -f "$SW_CONFIG_FILE" ]]; then source "$SW_CONFIG_FILE"; fi
CACHE="$ROOT/cache"                       # downloads, on the share
IMAGE="${SW_IMAGE:-$ROOT/swwine.sparsebundle}"  # holds Wine + prefix, on the share
IMAGE_SIZE="200g"
VOL="${SW_VOL:-/Volumes/SWWine}"

# 11.16 because scripts/patches/ are byte-exact binary patches for this build. Stock
# 11.21 hung forever compiling 32-bit .NET under Rosetta (see README).
WINE_VERSION="11.16"
WINE_FLAVOR="staging"
WINE_APP="$VOL/wine-$WINE_FLAVOR-$WINE_VERSION/Wine Staging.app"
WINE_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/$WINE_VERSION/wine-$WINE_FLAVOR-$WINE_VERSION-osx64.tar.xz"
WINETRICKS_VERSION="20260125"
WINETRICKS_URL="https://raw.githubusercontent.com/Winetricks/winetricks/$WINETRICKS_VERSION/src/winetricks"

export WINEARCH=win64
export WINEPREFIX="${SW_PREFIX:-$VOL/prefix-$WINE_VERSION}"
export W_CACHE="$CACHE/winetricks"        # winetricks must not fill the local disk
export XDG_CACHE_HOME="$CACHE/xdg"
export TMPDIR="$VOL/tmp"
export PATH="$WINE_APP/Contents/Resources/wine/bin:$VOL/bin:/opt/homebrew/bin:$PATH"
export WINEDEBUG="${WINEDEBUG:--all}"
