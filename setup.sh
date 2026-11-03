#!/bin/zsh
# First-time Wine preparation. Does not install licensed SOLIDWORKS media.
set -eu
setup_root="${0:A:h}"
stages=(01-storage.sh 02-wine.sh 03-prefix.sh stop-prefix build-shell32.sh install-ntdll-shim.sh build-mac-gdi.sh build-button-capture.sh)
if (( $# > 1 )); then print -u2 'Usage: ./setup.sh [--dry-run|--help]'; exit 2; fi
case "${1:-}" in
  --help|-h)
    print 'Usage: ./setup.sh [--dry-run]'
    print 'Prepare Wine for a first SOLIDWORKS installation. See README.md for the remaining steps.'
    exit 0 ;;
  --dry-run)
    for stage in "${stages[@]}"; do
      if [[ "$stage" == stop-prefix ]]; then print 'Stop the newly initialized Wine prefix'
      else print "scripts/$stage"; fi
    done
    exit 0 ;;
  '') ;;
  *) print -u2 'Usage: ./setup.sh [--dry-run|--help]'; exit 2 ;;
esac
source "$setup_root/scripts/env.sh"
# Refuse before creating files, mounting images or starting dependencies.
python3 "$setup_root/scripts/tools/require-stopped.py" "$WINE_APP/Contents/Resources/wine/bin/wineserver"
if [[ -f "$WINEPREFIX/drive_c/Program Files/Dassault Systemes/3DEXPERIENCE Launcher/3DEXPERIENCELauncher.exe" ]]; then
  print -u2 'This prefix already has the Launcher installed. Use the Mac app shortcut, or configure a separate image and prefix for a new installation.'
  exit 1
fi
"$setup_root/scripts/tools/check-setup-requirements.sh"
if [[ "${SW_CONFIG_FILE:h:A}" == "$setup_root" && "${SW_CONFIG_FILE:t}" == config.local.zsh && ! -f "$SW_CONFIG_FILE" ]]; then
  cp "$setup_root/config.example.zsh" "$SW_CONFIG_FILE"
fi
for stage in "${stages[@]}"; do
  if [[ "$stage" == stop-prefix ]]; then
    print 'Stopping the newly initialized Wine prefix…'
    wineserver -k
    wineserver -w
  else
    print "Running $stage…"
    "$setup_root/scripts/$stage"
  fi
done
print 'Wine preparation complete. Continue with Install SOLIDWORKS in README.md.'
