#!/bin/zsh
# Standalone download entry point; no Git, Python or Wine required beforehand.
set -eu
[[ "$(uname -s)" == Darwin ]] || { print -u2 'This installer requires macOS.'; exit 1; }
if (( $# )); then print -u2 'Usage: zsh install.sh'; exit 2; fi
install_root="${SW_INSTALL_DIR:-$HOME/SolidWorksMakerMac}"
[[ ! -e "$install_root" ]] || {
  print -u2 "Installation folder already exists: $install_root"
  print -u2 "To continue an existing setup, run: zsh ${(q)install_root}/scripts/install-guided.sh"
  exit 1
}
# Download into a private temporary directory; preserve any existing installation.
work="$(mktemp -d /private/tmp/solidworks-maker.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT
curl -fL --retry 3 https://github.com/lazy-jubei/solidworks-maker-mac/archive/refs/heads/main.tar.gz -o "$work/project.tar.gz"
tar -xzf "$work/project.tar.gz" -C "$work"
mkdir -p "${install_root:h}"
# Atomic directory creation refuses a competing or existing installation.
mkdir "$install_root"
cp -R "$work/solidworks-maker-mac-main/." "$install_root/"
zsh "$install_root/scripts/install-guided.sh"
