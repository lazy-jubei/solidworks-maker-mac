#!/bin/zsh
# Standalone download entry point; no Git, Python or Wine required beforehand.
set -eu
[[ "$(uname -s)" == Darwin ]] || { print -u2 'This installer requires macOS.'; exit 1; }
(( $# <= 1 )) || { print -u2 'Usage: zsh install.sh [--update]'; exit 2; }
case "${1:-}" in ''|--update) ;; *) print -u2 'Usage: zsh install.sh [--update]'; exit 2;; esac
install_root="${SW_INSTALL_DIR:-$HOME/SolidWorksMakerMac}"
updating=0
update_lock=''
if [[ -e "$install_root" ]]; then
  [[ -f "$install_root/scripts/env.sh" && ! -e "$install_root/.git" && ! -L "$install_root" ]] || {
    print -u2 "Not updating an unrecognized folder or development checkout: $install_root"; exit 1
  }
  updating=1
  update_lock="$install_root/.sw-update-lock"
  mkdir "$update_lock" 2>/dev/null || { print -u2 'Another update is running (or left .sw-update-lock after interruption).'; exit 1; }
elif [[ "${1:-}" == --update ]]; then
  print -u2 "Existing installation not found: $install_root"; exit 1
fi
# Download into a private temporary directory; preserve any existing installation.
work=''
trap '[[ -z "$work" ]] || rm -rf -- "$work"; [[ -z "$update_lock" ]] || rmdir "$update_lock"' EXIT
work="$(mktemp -d /private/tmp/solidworks-maker.XXXXXX)"
# The release archive and its checksum are published together. No Git is needed.
release=https://github.com/lazy-jubei/solidworks-maker-mac/releases/latest/download
curl --proto '=https' -fL --retry 3 "$release/solidworks-maker-mac.tar.gz" -o "$work/solidworks-maker-mac.tar.gz"
curl --proto '=https' -fL --retry 3 "$release/SHA256SUMS" -o "$work/SHA256SUMS"
( cd "$work"; /usr/bin/awk '$2 == "solidworks-maker-mac.tar.gz" {print}' SHA256SUMS > selected.sha256
  [[ -s selected.sha256 ]] || { print -u2 'Release checksum is missing.'; exit 1; }
  shasum -a 256 -c selected.sha256 )
tar -xzf "$work/solidworks-maker-mac.tar.gz" -C "$work"
folders=("$work"/solidworks-maker-mac-*(N/))
(( ${#folders} == 1 )) || { print -u2 'Unexpected release archive.'; exit 1; }
source_root="$folders[1]"
if (( updating )); then
  python3 "$source_root/scripts/tools/update-project.py" "$source_root" "$install_root"
  # The Finder app embeds a small copy of the launch scripts; refresh it too.
  zsh "$install_root/scripts/09-mac-launcher.sh"
  print 'Script update complete. To update Wine separately, quit SolidWorks and Wine, then run:'
  print -r -- "zsh ${(q)install_root}/scripts/update.sh --wine"
  exit 0
fi
mkdir -p "${install_root:h}"
# Atomic directory creation refuses a competing or existing installation.
mkdir "$install_root"
cp -R "$source_root/." "$install_root/"
zsh "$install_root/scripts/install-guided.sh"
