#!/bin/zsh
# Interactive first installation. Credentials are entered only in vendor windows.
set -eu
source "${0:A:h}/env.sh"
ask() { read -r "?$1"; }
[[ -r /dev/tty ]] || { print -u2 'Run this installer in Terminal.'; exit 1; }
exec </dev/tty
state="$CACHE/install-state"
# Completed stages are recorded only after success. Never replace a running runtime.
if [[ ! -f "$state/wine" ]]; then
  "$ROOT/setup.sh"
  mkdir -p "$state"
  touch "$state/wine"
else
  python3 "$ROOT/scripts/tools/require-stopped.py" "$WINE_APP/Contents/Resources/wine/bin/wineserver"
  "$ROOT/scripts/01-storage.sh"
fi
shortcut="$WINEPREFIX/drive_c/users/Public/Desktop/SOLIDWORKS Design.lnk"
if [[ ! -f "$state/launcher" || ! -f "$state/runtime" || ! -f "$shortcut" ]]; then
  read -r 'dashboard?Paste your official Makers dashboard URL: '
  [[ "$dashboard" == https://* ]] || { print -u2 'Use the HTTPS URL from your Makers account.'; exit 1; }
  "$ROOT/scripts/open-dashboard.sh" "$dashboard" &
fi
if [[ ! -f "$state/runtime" ]]; then
  if [[ ! -f "$state/launcher" ]]; then
    print 'Sign in and download the 3DEXPERIENCE Launcher in the browser.'
    print 'Save its MSI anywhere, then paste its file path below (you can drag it from Finder).'
    read -r 'msi?Launcher MSI path: '
    msi="${(Q)msi}"
    [[ -f "$msi" && "${msi:e:l}" == msi ]] || { print -u2 'Launcher MSI not found.'; exit 1; }
    mkdir -p "$CACHE/installers"
    destination="$CACHE/installers/3DEXPERIENCELauncher.msi"
    if [[ "${msi:A}" != "${destination:A}" ]]; then cp "$msi" "$destination"; fi
    "$ROOT/scripts/04-launcher.sh"
    touch "$state/launcher"
  fi
  "$ROOT/scripts/05-webview2.sh"
  "$ROOT/scripts/06-settings.sh"
  wineserver -k
  wineserver -w
  "$ROOT/scripts/install-dxmt.sh"
  "$ROOT/scripts/build-signin-tools.sh"
  touch "$state/runtime"
fi
if [[ ! -f "$shortcut" ]]; then
  print 'Use Install SOLIDWORKS on your Makers dashboard. Complete the vendor installer.'
  ask 'Press Return when SOLIDWORKS installation has finished: '
fi
[[ -f "$shortcut" ]] || { print -u2 'SOLIDWORKS desktop shortcut not found; installation is incomplete.'; exit 1; }
python3 "$ROOT/scripts/tools/configure-shortcut.py" "$shortcut" "$SW_CONFIG_FILE"
"$ROOT/scripts/09-mac-launcher.sh"
print 'Setup complete. Sign in in the SOLIDWORKS window. Future launches: SolidWorks (Wine) in Applications.'
"$ROOT/scripts/10-fresh-signin.sh"
