#!/bin/zsh
# Install missing build prerequisites using the vendor's interactive installers.
# Homebrew's installer now refuses Intel Macs, so an Intel Mac without Homebrew gets
# bison and cabextract built from their release sources into tools/ instead, and uses
# the Command Line Tools' python3.
set -eu
[[ "$(uname -s)" == Darwin ]] || { print -u2 'This setup requires macOS.'; exit 1; }
export TMPDIR=/private/tmp
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tools="${SW_TOOLS:-${0:A:h:h:h}/tools}"
export PATH="$PATH:$tools/bin"
if ! xcrun --find clang >/dev/null 2>&1; then
  xcode-select --install
  print 'Complete the Command Line Tools installation in the macOS window.'
  read -r '?Press Return when installation has finished: '
  xcrun --find clang >/dev/null
fi
host_arm64=0
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]]; then host_arm64=1; fi

# Build <name>-<version> from a checksummed release tarball into $tools, unless present.
build_tool() {
  local name="$1" version="$2" url="$3" sha="$4"
  shift 4
  if [[ -x "$tools/bin/$name" ]] && "$tools/bin/$name" --version 2>/dev/null | grep -qF -- "$version"; then
    return 0
  fi
  print "Building $name $version from source (Homebrew does not support Intel Macs)…"
  mkdir -p "$tools"
  local work log="$tools/$name-build.log"
  work="$(mktemp -d /private/tmp/solidworks-$name.XXXXXX)"
  local archive="$work/${url:t}"
  curl -fL -o "$archive" "$url"
  print -r -- "$sha  $archive" | shasum -a 256 -c - >/dev/null
  tar -xf "$archive" -C "$work"
  # Autotools breaks on spaces in --prefix, and the checkout may live under one, so
  # install into a space-free staging prefix and copy it into $tools afterwards.
  if ! ( cd "$work/$name-$version" && ./configure --prefix="$work/prefix" "$@" \
         && make -j"$(/usr/sbin/sysctl -n hw.ncpu)" && make install \
         && mkdir -p "$tools" && cp -R "$work/prefix/." "$tools/" ) > "$log" 2>&1; then
    rm -rf -- "$work"
    print -u2 "Building $name failed; see $log"
    return 1
  fi
  rm -rf -- "$work"
}

bison_bin=""
if ! command -v brew >/dev/null && (( host_arm64 )); then
  brew_installer="$(mktemp /private/tmp/solidworks-homebrew.XXXXXX)"
  trap 'rm -f -- "$brew_installer"' EXIT
  curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$brew_installer"
  /bin/bash "$brew_installer"
fi
if command -v brew >/dev/null; then
  brew_prefix="$(brew --prefix)"
  export PATH="$brew_prefix/bin:$PATH"
  missing=()
  for formula in python bison cabextract; do
    [[ -d "$brew_prefix/opt/$formula" ]] || missing+=("$formula")
  done
  if (( ${#missing} )); then brew install "${missing[@]}"; fi
  bison_bin="$brew_prefix/opt/bison/bin/bison"
else
  build_tool bison 3.8.2 https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.xz \
    9bba0214ccf7f1079c5d59210045227bcf619519840ebfa80cd3849cff5a5bf2 --disable-nls --enable-relocatable
  build_tool cabextract 1.11 https://www.cabextract.org.uk/cabextract-1.11.tar.gz \
    b5546db1155e4c718ff3d4b278573604f30dd64c3c5bfd4657cd089b823a3ac6
  bison_bin="$tools/bin/bison"
fi
if (( host_arm64 )) && ! arch -x86_64 /usr/bin/true 2>/dev/null; then
  /usr/sbin/softwareupdate --install-rosetta
fi
command -v python3 >/dev/null
command -v cabextract >/dev/null
[[ -x "$bison_bin" ]]
arch -x86_64 /usr/bin/true
