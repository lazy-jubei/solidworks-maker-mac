#!/bin/zsh
# Interactive installation into a new Wine prefix (any previous one is deleted first).
# Credentials are entered only in vendor windows.
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
stage='starting'
dashboard_pid=''
wine_started=0
shortcut="$WINEPREFIX/drive_c/users/Public/Desktop/SOLIDWORKS Design.lnk"
wineserver_bin="$WINE_APP/Contents/Resources/wine/bin/wineserver"
# The dashboard browser is only needed until SOLIDWORKS is installed; never leave it behind.
close_dashboard() {
  if [[ -n "$dashboard_pid" ]]; then
    kill "$dashboard_pid" 2>/dev/null || true
    wait "$dashboard_pid" 2>/dev/null || true
    dashboard_pid=''
  fi
}
# Stopping setup also stops the Wine it started (the Launcher service), so nothing is left
# running and the next attempt can start cleanly. After success SOLIDWORKS keeps running.
stop_wine() {
  if (( wine_started )); then wineserver -k 2>/dev/null || true; wine_started=0; fi
}
trap 'rc=$?; close_dashboard; if (( rc != 0 )); then stop_wine; fi; if (( rc != 0 && rc != 130 )); then installer_failed "$stage"; fi' EXIT
trap 'exit 130' HUP INT TERM

# Every run installs into a new Wine prefix: the previous one is deleted first. The Wine
# build and downloads stay cached on the disk image, and a clean prepared prefix is kept,
# so a reinstall only copies it. The hands-on steps (sign in, download the Launcher) come
# first, so the long preparation can then run unattended.
installer_stage launcher 'checking for an earlier installation'
if [[ -d "$IMAGE" ]]; then "$ROOT/scripts/01-storage.sh"; fi
welcome='This sets up SOLIDWORKS for Makers on your Mac in the five steps listed on the left.

You are needed at two points. First, sign in to your Makers account in a separate browser and download the 3DEXPERIENCE Launcher (a few minutes). Then Wine is prepared and components are installed without you: 30–60 minutes the first time, a few minutes after that. At the end, you install SOLIDWORKS from your dashboard.'
if [[ -f "$shortcut" ]]; then
  installer_message "SOLIDWORKS is already installed. Continuing deletes its Wine prefix (the installed SOLIDWORKS and anything saved on its C: drive) and installs everything again from scratch.

Quit SOLIDWORKS before continuing. To just use SOLIDWORKS, quit this installer and open SolidWorks (Wine) in your Applications folder." 'Delete and Reinstall' 'Reinstall SOLIDWORKS?'
else
  installer_message "$welcome" 'Start' 'Welcome'
fi

installer_stage launcher 'opening the SOLIDWORKS sign-in browser'
dashboard="$(installer_ask_dashboard)"
# The browser logs a lot; keep it out of the installer's own messages.
"$ROOT/scripts/open-dashboard.sh" "$dashboard" < /dev/null > "$ROOT/logs/dashboard-browser.log" 2>&1 &
dashboard_pid=$!
installer_stage launcher 'choosing the Launcher installer'
msi="$(installer_choose_msi)"
mkdir -p "$CACHE/installers"
destination="$CACHE/installers/3DEXPERIENCELauncher.msi"
if [[ "${msi:A}" != "${destination:A}" ]]; then cp "$msi" "$destination"; fi

if [[ -e "$WINEPREFIX" ]]; then
  installer_stage wine 'deleting the previous Wine prefix'
  # Only ever delete something that is recognisably a Wine prefix.
  [[ -d "$WINEPREFIX/drive_c" ]] || { print -u2 "Not deleting $WINEPREFIX: it does not look like a Wine prefix."; exit 1; }
  if [[ -x "$wineserver_bin" ]]; then
    WINEPREFIX="$WINEPREFIX" "$wineserver_bin" -k 2>/dev/null || true
    WINEPREFIX="$WINEPREFIX" "$wineserver_bin" -w 2>/dev/null || true
  fi
  rm -rf -- "$WINEPREFIX"
fi
rm -rf -- "$CACHE/install-state"
wine_started=1
installer_stage wine 'preparing Wine'
installer_notify 'You can leave this running; the terminal shows its progress.'
"$ROOT/setup.sh"
installer_notify 'Wine is ready.'
installer_stage components 'installing the 3DEXPERIENCE Launcher'
"$ROOT/scripts/04-launcher.sh"
installer_stage components 'installing WebView2'
"$ROOT/scripts/05-webview2.sh"
installer_stage components 'applying Wine settings'
"$ROOT/scripts/06-settings.sh"
wineserver -k
wineserver -w
installer_stage components 'installing DXMT for WebView2'
"$ROOT/scripts/install-dxmt.sh"
installer_stage components 'building sign-in tools'
"$ROOT/scripts/build-signin-tools.sh"
if [[ ! -f "$shortcut" ]]; then
  # The dashboard's Install button hands off to the Launcher, a Wine service. Earlier steps
  # stop Wine, so start its services (wineboot) before sending anyone to the dashboard.
  installer_stage solidworks 'starting the 3DEXPERIENCE Launcher'
  wine wineboot > "$ROOT/logs/launcher-service.log" 2>&1
  installer_stage solidworks 'waiting for the SOLIDWORKS installation'
  install_text='1. In the browser window (Google Chrome for Testing), sign in to your Makers dashboard if needed.
2. Click Install SOLIDWORKS. If the 3DEXPERIENCE Launcher asks whether to trust the site, allow it.
3. The SOLIDWORKS installer opens in its own window and downloads several gigabytes. Finish it there.

The 3DEXPERIENCE Launcher you installed is only the helper that runs this installer, not SOLIDWORKS itself.'
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
