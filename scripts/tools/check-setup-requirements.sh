#!/bin/zsh
# Install missing build prerequisites. bison and cabextract come from MacPorts, which
# supports Intel and Apple Silicon Macs (scripts/tools/macports.sh installs it if needed);
# python3 and the compilers come from Apple's Command Line Tools.
set -eu
[[ "$(uname -s)" == Darwin ]] || { print -u2 'This setup requires macOS.'; exit 1; }
export TMPDIR=/private/tmp
source "${0:A:h}/macports.sh"
export PATH="$MACPORTS_BIN:$PATH"
if ! xcrun --find clang >/dev/null 2>&1; then
  xcode-select --install
  print 'Complete the Command Line Tools installation in the macOS window.'
  read -r '?Press Return when installation has finished: '
  xcrun --find clang >/dev/null
fi
host_arm64=0
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]]; then host_arm64=1; fi
macports_install bison cabextract
if (( host_arm64 )) && ! arch -x86_64 /usr/bin/true 2>/dev/null; then
  /usr/sbin/softwareupdate --install-rosetta
fi
command -v python3 >/dev/null
command -v cabextract >/dev/null
[[ -x "$MACPORTS_BIN/bison" ]]
arch -x86_64 /usr/bin/true
