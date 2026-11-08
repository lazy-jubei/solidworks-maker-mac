#!/bin/zsh
# Interactive first installation. Credentials are entered only in vendor windows.
# In a desktop session this opens the installer window (see tools/installer-ui.zsh),
# which runs this script again inside it; otherwise prompts are dialogs or Terminal.
set -eu
source "${0:A:h}/env.sh"
source "${0:A:h}/tools/installer-ui.zsh"
mkdir -p "$ROOT/logs"
if [[ "$installer_ui" == window ]]; then
  if installer_open_window; then
    print 'The installer window is open. You can close this Terminal window.'
    exit 0
  fi
  installer_ui=dialogs
fi
if [[ "$installer_ui" != app ]]; then
  [[ -r /dev/tty ]] || { print -u2 'Run this installer in Terminal.'; exit 1; }
  exec </dev/tty
fi
state="$CACHE/install-state"
stage='starting'
dashboard_pid=''
# The dashboard browser is only needed until SOLIDWORKS is installed; never leave it behind.
close_dashboard() {
  if [[ -n "$dashboard_pid" ]]; then
    kill "$dashboard_pid" 2>/dev/null || true
    wait "$dashboard_pid" 2>/dev/null || true
    dashboard_pid=''
  fi
}
trap 'rc=$?; close_dashboard; if (( rc != 0 && rc != 130 )); then installer_failed "$stage"; fi' EXIT
trap 'exit 130' HUP INT TERM

if [[ ! -f "$state/wine" ]]; then
  installer_message 'This installer prepares Wine and then guides you through installing SOLIDWORKS with your own Makers subscription.

Preparing Wine downloads and builds components and can take 30–60 minutes.' 'Start' 'Welcome'
fi
# Completed stages are recorded only after success. Never replace a running runtime.
if [[ ! -f "$state/wine" ]]; then
  installer_stage wine 'preparing Wine'
  installer_notify 'This takes a while; the terminal shows its progress.'
  "$ROOT/setup.sh"
  mkdir -p "$state"
  touch "$state/wine"
  installer_notify 'Wine is ready.'
else
  installer_stage wine 'mounting the Wine disk image'
  python3 "$ROOT/scripts/tools/require-stopped.py" "$WINE_APP/Contents/Resources/wine/bin/wineserver"
  "$ROOT/scripts/01-storage.sh"
fi
shortcut="$WINEPREFIX/drive_c/users/Public/Desktop/SOLIDWORKS Design.lnk"
if [[ ! -f "$state/launcher" || ! -f "$state/runtime" || ! -f "$shortcut" ]]; then
  installer_stage launcher 'opening the SOLIDWORKS sign-in browser'
  dashboard="$(installer_ask_dashboard)"
  # The browser logs a lot; keep it out of the installer's own messages.
  "$ROOT/scripts/open-dashboard.sh" "$dashboard" < /dev/null > "$ROOT/logs/dashboard-browser.log" 2>&1 &
  dashboard_pid=$!
fi
if [[ ! -f "$state/runtime" ]]; then
  if [[ ! -f "$state/launcher" ]]; then
    installer_stage launcher 'choosing the Launcher installer'
    msi="$(installer_choose_msi)"
    mkdir -p "$CACHE/installers"
    destination="$CACHE/installers/3DEXPERIENCELauncher.msi"
    if [[ "${msi:A}" != "${destination:A}" ]]; then cp "$msi" "$destination"; fi
    installer_stage components 'installing the 3DEXPERIENCE Launcher'
    installer_notify 'Installing the 3DEXPERIENCE Launcher…'
    "$ROOT/scripts/04-launcher.sh"
    touch "$state/launcher"
  fi
  installer_stage components 'installing WebView2'
  installer_notify 'Installing WebView2 and sign-in components. This takes a few minutes.'
  "$ROOT/scripts/05-webview2.sh"
  installer_stage components 'applying Wine settings'
  "$ROOT/scripts/06-settings.sh"
  wineserver -k
  wineserver -w
  installer_stage components 'installing DXMT for WebView2'
  "$ROOT/scripts/install-dxmt.sh"
  installer_stage components 'building sign-in tools'
  "$ROOT/scripts/build-signin-tools.sh"
  touch "$state/runtime"
fi
if [[ ! -f "$shortcut" ]]; then
  installer_stage solidworks 'waiting for the SOLIDWORKS installation'
  install_text='In the browser, click Install SOLIDWORKS on your Makers dashboard. The SOLIDWORKS installer opens in its own window and downloads several gigabytes: finish it there.

The Launcher you installed earlier is only the helper that runs this installer; it is not SOLIDWORKS itself.'
  installer_message "$install_text" 'Continue' 'Install SOLIDWORKS' "$shortcut"
  # Continuing early asks again rather than failing.
  while [[ ! -f "$shortcut" ]]; do
    installer_message "SOLIDWORKS is not installed yet: its desktop shortcut was not found. Finish the SOLIDWORKS installer, then click Continue.

$install_text" 'Continue' 'Install SOLIDWORKS' "$shortcut"
  done
fi
close_dashboard
installer_stage finish 'creating the Mac app'
python3 "$ROOT/scripts/tools/configure-shortcut.py" "$shortcut" "$SW_CONFIG_FILE"
"$ROOT/scripts/09-mac-launcher.sh"
if [[ "$installer_ui" == app ]]; then
  # Started apart from the window, so closing it leaves SOLIDWORKS running.
  installer_stage finish 'starting SOLIDWORKS'
  "$ROOT/scripts/10-fresh-signin.sh" < /dev/null > "$ROOT/logs/first-launch.log" 2>&1 &!
  installer_emit finished 'SOLIDWORKS is opening: sign in in its window. This can take a minute.

Future launches: open SolidWorks (Wine) in your Applications folder.'
  exit 0
fi
installer_message 'Setup complete. SOLIDWORKS opens next: sign in in its window.

Future launches: open SolidWorks (Wine) in your Applications folder.' 'Open SOLIDWORKS'
print 'Setup complete. Sign in in the SOLIDWORKS window. Future launches: SolidWorks (Wine) in Applications.'
installer_stage finish 'starting SOLIDWORKS'
"$ROOT/scripts/10-fresh-signin.sh"
