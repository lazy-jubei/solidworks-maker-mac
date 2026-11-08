#!/bin/zsh
# Interactive first installation. Credentials are entered only in vendor windows.
# Prompts appear as macOS dialogs (see tools/installer-ui.zsh); Terminal shows progress.
set -eu
source "${0:A:h}/env.sh"
source "${0:A:h}/tools/installer-ui.zsh"
[[ -r /dev/tty ]] || { print -u2 'Run this installer in Terminal.'; exit 1; }
exec </dev/tty
state="$CACHE/install-state"
mkdir -p "$ROOT/logs"
stage='starting'
trap 'rc=$?; if (( rc != 0 && rc != 130 )); then installer_failed "$stage"; fi' EXIT

if [[ ! -f "$state/wine" ]]; then
  installer_message 'This installer prepares Wine and then guides you through installing SOLIDWORKS with your own Makers subscription.

Preparing Wine downloads and builds components and can take 30–60 minutes. You can follow its progress in Terminal.' 'Start'
fi
# Completed stages are recorded only after success. Never replace a running runtime.
if [[ ! -f "$state/wine" ]]; then
  stage='preparing Wine'
  installer_notify 'Preparing Wine. This takes a while; progress is shown in Terminal.'
  "$ROOT/setup.sh"
  mkdir -p "$state"
  touch "$state/wine"
  installer_notify 'Wine is ready.'
else
  stage='mounting the Wine disk image'
  python3 "$ROOT/scripts/tools/require-stopped.py" "$WINE_APP/Contents/Resources/wine/bin/wineserver"
  "$ROOT/scripts/01-storage.sh"
fi
shortcut="$WINEPREFIX/drive_c/users/Public/Desktop/SOLIDWORKS Design.lnk"
if [[ ! -f "$state/launcher" || ! -f "$state/runtime" || ! -f "$shortcut" ]]; then
  stage='opening the SOLIDWORKS sign-in browser'
  dashboard="$(installer_ask_dashboard)"
  # The browser logs a lot; keep it out of the installer's own messages.
  "$ROOT/scripts/open-dashboard.sh" "$dashboard" > "$ROOT/logs/dashboard-browser.log" 2>&1 &
fi
if [[ ! -f "$state/runtime" ]]; then
  if [[ ! -f "$state/launcher" ]]; then
    stage='choosing the Launcher installer'
    msi="$(installer_choose_msi)"
    mkdir -p "$CACHE/installers"
    destination="$CACHE/installers/3DEXPERIENCELauncher.msi"
    if [[ "${msi:A}" != "${destination:A}" ]]; then cp "$msi" "$destination"; fi
    stage='installing the 3DEXPERIENCE Launcher'
    installer_notify 'Installing the 3DEXPERIENCE Launcher…'
    "$ROOT/scripts/04-launcher.sh"
    touch "$state/launcher"
  fi
  installer_notify 'Installing WebView2 and sign-in components. This takes a few minutes.'
  stage='installing WebView2'
  "$ROOT/scripts/05-webview2.sh"
  stage='applying Wine settings'
  "$ROOT/scripts/06-settings.sh"
  wineserver -k
  wineserver -w
  stage='installing DXMT for WebView2'
  "$ROOT/scripts/install-dxmt.sh"
  stage='building sign-in tools'
  "$ROOT/scripts/build-signin-tools.sh"
  touch "$state/runtime"
fi
if [[ ! -f "$shortcut" ]]; then
  stage='waiting for the SOLIDWORKS installation'
  installer_message 'On your Makers dashboard in the browser, choose Install SOLIDWORKS and complete the vendor installer.

Click Continue once the SOLIDWORKS installation has finished.' 'Continue'
fi
stage='checking the SOLIDWORKS installation'
[[ -f "$shortcut" ]] || { print -u2 'SOLIDWORKS desktop shortcut not found; installation is incomplete.'; exit 1; }
stage='creating the Mac app'
python3 "$ROOT/scripts/tools/configure-shortcut.py" "$shortcut" "$SW_CONFIG_FILE"
"$ROOT/scripts/09-mac-launcher.sh"
installer_message 'Setup complete. SOLIDWORKS opens next: sign in in its window.

Future launches: open SolidWorks (Wine) in your Applications folder.' 'Open SOLIDWORKS'
print 'Setup complete. Sign in in the SOLIDWORKS window. Future launches: SolidWorks (Wine) in Applications.'
stage='starting SOLIDWORKS'
"$ROOT/scripts/10-fresh-signin.sh"
