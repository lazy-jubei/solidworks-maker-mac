# Shared settings. Source this: `source scripts/env.sh`
# Resolve relative to this checkout, including when sourced from another directory.
ROOT="${SW_PROJECT_ROOT:-${${(%):-%x}:A:h:h}}"
SW_CONFIG_FILE="${SW_CONFIG_FILE:-$ROOT/config.local.zsh}"
if [[ -f "$SW_CONFIG_FILE" ]]; then source "$SW_CONFIG_FILE"; fi
CACHE="$ROOT/cache"                       # downloads, on the share
IMAGE="${SW_IMAGE:-$ROOT/swwine.sparsebundle}"  # holds Wine + prefix, on the share
IMAGE_SIZE="200g"
VOL="${SW_VOL:-/Volumes/SWWine}"
# Source-built bison/cabextract for Intel Macs, which Homebrew no longer supports.
export SW_TOOLS="${SW_TOOLS:-$ROOT/tools}"

# 11.16 because scripts/patches/ are byte-exact binary patches for this build. Stock
# 11.21 hung forever compiling 32-bit .NET under Rosetta.
WINE_VERSION="11.16"
WINE_FLAVOR="staging"
WINE_APP="$VOL/wine-$WINE_FLAVOR-$WINE_VERSION/Wine Staging.app"
WINE_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/$WINE_VERSION/wine-$WINE_FLAVOR-$WINE_VERSION-osx64.tar.xz"
WINETRICKS_VERSION="20260125"
WINETRICKS_URL="https://raw.githubusercontent.com/Winetricks/winetricks/$WINETRICKS_VERSION/src/winetricks"

# Detect physical Apple Silicon even when the shell itself runs under Rosetta.
SW_HOST_ARM64=0
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]]; then
  SW_HOST_ARM64=1
fi

export WINEARCH=win64
export WINEPREFIX="${SW_PREFIX:-$VOL/prefix-$WINE_VERSION}"
export W_CACHE="$CACHE/winetricks"        # winetricks must not fill the local disk
export XDG_CACHE_HOME="$CACHE/xdg"
export TMPDIR="$VOL/tmp"
export PATH="$WINE_APP/Contents/Resources/wine/bin:$VOL/bin:/opt/homebrew/bin:/usr/local/bin:$PATH:$SW_TOOLS/bin"
export WINEDEBUG="${WINEDEBUG:--all}"

# PATH for Wine source builds: $1 (llvm-mingw) first, then bison 3 from Homebrew when
# installed, otherwise the copy that check-setup-requirements.sh built into tools/.
sw_build_path() {
  local brew_prefix="" bison_dir="$SW_TOOLS/bin"
  if command -v brew >/dev/null; then brew_prefix="$(brew --prefix)"; fi
  if [[ -n "$brew_prefix" && -x "$brew_prefix/opt/bison/bin/bison" ]]; then
    bison_dir="$brew_prefix/opt/bison/bin"
  fi
  print -r -- "$1:$bison_dir:/usr/bin:/bin${brew_prefix:+:$brew_prefix/bin}:$SW_TOOLS/bin"
}
