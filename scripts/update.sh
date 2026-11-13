#!/bin/zsh
# Refresh project sources without entering the destructive guided installer.
set -eu
root="${0:A:h:h}"
case "${1:-}" in
  '') export SW_INSTALL_DIR="$root"; exec zsh "$root/install.sh" --update ;;
  --wine) exec zsh "$root/scripts/update-wine.sh" ;;
  *) print -u2 'Usage: scripts/update.sh [--wine]'; exit 2 ;;
esac
