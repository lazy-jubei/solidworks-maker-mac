#!/bin/zsh
# First-time Wine preparation. Does not install licensed SOLIDWORKS media.
set -eu
setup_root="${0:A:h}"
stages=(01-storage.sh 02-wine.sh 03-prefix.sh stop-prefix build-shell32.sh install-ntdll-shim.sh build-mac-gdi.sh build-button-capture.sh)
if (( $# > 1 )); then print -u2 'Usage: ./setup.sh [--dry-run|--help]'; exit 2; fi
case "${1:-}" in
  --help|-h)
    print 'Usage: ./setup.sh [--dry-run]'
    print 'Prepare Wine for a first SOLIDWORKS installation. Use scripts/install-guided.sh for the full installation.'
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
# This guard must also work before Python has been installed.
setup_server="$WINE_APP/Contents/Resources/wine/bin/wineserver"
setup_processes="$(ps -axo comm=)"
for setup_process in "${(@f)setup_processes}"; do
  setup_process="${setup_process#"${setup_process%%[![:space:]]*}"}"
  if [[ "${setup_process:t}" == wineserver && "${setup_process:A}" == "${setup_server:A}" ]]; then
    print -u2 'Save and close applications, then stop this Wine prefix before replacing its runtime.'
    exit 1
  fi
done
refuse_installed_prefix() {
  if [[ -f "$WINEPREFIX/drive_c/Program Files/Dassault Systemes/3DEXPERIENCE Launcher/3DEXPERIENCELauncher.exe" ]]; then
    print -u2 'This prefix already has the Launcher installed. Use the Mac app shortcut, or configure a separate image and prefix for a new installation.'
    exit 1
  fi
}
refuse_installed_prefix
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
    # An existing image may have been unmounted during the first check.
    if [[ "$stage" == 01-storage.sh ]]; then refuse_installed_prefix; fi
  fi
done
print 'Wine preparation complete.'
