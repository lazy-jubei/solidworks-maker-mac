#!/bin/zsh
# Install missing build prerequisites using the vendor's interactive installers.
set -eu
[[ "$(uname -s)" == Darwin ]] || { print -u2 'This setup requires macOS.'; exit 1; }
export TMPDIR=/private/tmp
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! xcrun --find clang >/dev/null 2>&1; then
  xcode-select --install
  print 'Complete the Command Line Tools installation in the macOS window.'
  read -r '?Press Return when installation has finished: '
  xcrun --find clang >/dev/null
fi
if ! command -v brew >/dev/null; then
  brew_installer="$(mktemp /private/tmp/solidworks-homebrew.XXXXXX)"
  trap 'rm -f -- "$brew_installer"' EXIT
  curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$brew_installer"
  /bin/bash "$brew_installer"
fi
brew_prefix="$(brew --prefix)"
export PATH="$brew_prefix/bin:$PATH"
missing=()
for formula in python bison cabextract; do
  [[ -d "$brew_prefix/opt/$formula" ]] || missing+=("$formula")
done
if (( ${#missing} )); then brew install "${missing[@]}"; fi
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]] && ! arch -x86_64 /usr/bin/true 2>/dev/null; then
  /usr/sbin/softwareupdate --install-rosetta
fi
command -v python3 >/dev/null
command -v cabextract >/dev/null
[[ -x "$brew_prefix/opt/bison/bin/bison" ]]
arch -x86_64 /usr/bin/true
