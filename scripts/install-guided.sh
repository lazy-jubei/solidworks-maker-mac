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
dashboard=''
wine_started=0
shortcut="$WINEPREFIX/drive_c/users/Public/Desktop/SOLIDWORKS Design.lnk"
wineserver_bin="$WINE_APP/Contents/Resources/wine/bin/wineserver"
# The dashboard browser (Chrome) is only needed until SolidWorks is installed; never leave it
# behind. Its pid is kept in a file so a prompt running in $(...) can relaunch it too.
browser_pidfile="$ROOT/logs/dashboard-browser.pid"
rm -f -- "$browser_pidfile"
open_browser() {
  # Chrome logs a lot; keep it out of the installer's own messages.
  "$ROOT/scripts/open-dashboard.sh" "$dashboard" < /dev/null >> "$ROOT/logs/dashboard-browser.log" 2>&1 &
  print -r -- $! > "$browser_pidfile"
}
# The window's Relaunch Chrome button (installer-ui.zsh calls this for the Launcher download).
installer_reopen_browser() {
  local pid=''
  [[ -f "$browser_pidfile" ]] && pid="$(<"$browser_pidfile")"
  if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then open_browser; fi
}
close_dashboard() {
  local pid=''
  [[ -f "$browser_pidfile" ]] && pid="$(<"$browser_pidfile")"
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
    # Wait for it to close Chrome (it may not be this shell's child).
    for _ in {1..50}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  fi
  rm -f -- "$browser_pidfile"
}
# Stopping setup also stops the Wine it started (the Launcher service), so nothing is left
# running and the next attempt can start cleanly. After success SOLIDWORKS keeps running.
stop_wine() {
  if (( wine_started )); then wineserver -k 2>/dev/null || true; wine_started=0; fi
}
install_text='1. In the Chrome window, sign in to your SolidWorks Maker account.
2. Click Install SolidWorks. If asked to trust the site, click Allow.
3. Follow the SolidWorks installer when it opens.'
# Windows programs that run in the background of any prefix, never the SOLIDWORKS installer.
background_programs=(services winedevice svchost plugplay rpcss explorer conhost start wineboot
  rundll32 winemenubuilder mscorsvw ngen microsoftedgeupdate msedgewebview2 tabtip
  3dexperiencelauncher 3dexperiencelaunchersystray)
# installer_programs: prints "<pid> <program.exe>" for each foreground Windows program running
# in this Wine prefix. Other Wine installations on the Mac are told apart by their open files.
installer_programs() {
  local pid cmd name
  ps -axo pid=,command= | while read -r pid cmd; do
    [[ "$cmd" == [A-Za-z]:\\* ]] || continue
    name="${${cmd%%.[eE][xX][eE]*}##*\\}"
    (( ${background_programs[(Ie)${name:l}]} )) && continue
    lsof -p "$pid" -Fn 2>/dev/null | grep -qF -- "$WINEPREFIX/" || continue
    print -r -- "$pid $name.exe"
  done
}
# Requests the Launcher has received from a web page (its service log records each one).
launcher_requests() {
  local logs="$WINEPREFIX/drive_c/ProgramData/DassaultSystemes/3DEXPERIENCELauncher/logs/3DEXPERIENCELauncher_service"
  local files=("$logs"/*(N.))
  if (( ! ${#files} )); then print 0; return; fi
  cat -- "${files[@]}" < /dev/null 2>/dev/null | grep -c 'Request caught with URL' || true
}
# App mode: two steps the script follows by itself, with no Continue button. "Start from
# Chrome" waits for the dashboard to start the SOLIDWORKS installer; "Install SOLIDWORKS"
# lasts while the installer runs, and ends once SOLIDWORKS is installed and it has closed.
await_solidworks_app() {
  local start_title='Install SolidWorks from Chrome'
  local start_text='1. In the Chrome window, sign in to your SolidWorks Maker account.
2. Click Install SolidWorks. If asked to trust the site, click Allow.

This step continues on its own when the installer opens.'
  local phase=start found program requests0 requests noted=0 gone=0
  requests0="$(launcher_requests)"
  installer_stage start 'waiting for you in Chrome'
  installer_emit wait "$start_title" "$start_text" 'Waiting for you to click Install SolidWorks.' browser
  local reply
  while true; do
    # The window's Relaunch Chrome button arrives while this step is waiting.
    if read -r -t 0 reply && [[ "$reply" == @@relaunch ]]; then installer_reopen_browser; fi
    found="$(installer_programs | head -n 1)"
    program="${found#* }"
    if [[ -n "$found" ]]; then
      gone=0
      if [[ "$phase" == start ]]; then
        phase=installing
        installer_stage solidworks 'installing SolidWorks'
        installer_emit wait 'Installing SolidWorks' "Follow the SolidWorks installer in its own window. It downloads several gigabytes, so this can take a while.

This step continues on its own when the installer is done." "Running $program"
      elif [[ -f "$shortcut" ]]; then
        installer_notify 'SolidWorks is installed. Close the installer window to continue.'
      fi
    elif [[ -f "$shortcut" ]]; then
      return 0
    elif [[ "$phase" == installing ]]; then
      # Installers hand over between programs; only a lasting absence means it closed.
      if (( ++gone >= 7 )); then
        phase=start gone=0
        installer_stage start 'waiting for you in Chrome'
        installer_emit wait "$start_title" "$start_text" 'The installer closed before SolidWorks finished installing. Click Install SolidWorks again.' browser
      fi
    elif (( ! noted )); then
      requests="$(launcher_requests)"
      if (( requests > requests0 )); then
        noted=1
        installer_notify 'Chrome is connected to the Launcher. Click Install SolidWorks.'
      fi
    fi
    sleep "${SW_WATCH_INTERVAL:-3}"
  done
}
trap 'rc=$?; close_dashboard; if (( rc != 0 )); then stop_wine; fi; if (( rc != 0 && rc != 130 )); then installer_failed "$stage"; fi' EXIT
trap 'exit 130' HUP INT TERM

# Every run installs into a new Wine prefix: the previous one is deleted first. The Wine
# build and downloads stay cached on the disk image, and a clean prepared prefix is kept,
# so a reinstall only copies it. The hands-on steps (sign in, download the Launcher) come
# first, so the long preparation can then run unattended.
installer_stage launcher 'checking for an earlier install'
if [[ -d "$IMAGE" ]]; then "$ROOT/scripts/01-storage.sh"; fi
welcome='This installs SolidWorks Maker on your Mac.

You only need to do two things:
1. At the start, sign in to your SolidWorks Maker account in a Chrome window and download the 3DEXPERIENCE Launcher.
2. At the end, click Install SolidWorks in that Chrome window.

Everything in between runs on its own. The first time takes 30–60 minutes.'
if [[ -f "$shortcut" ]]; then
  installer_message "SolidWorks is already installed. Reinstalling deletes it, along with any files saved inside it, and installs everything again.

Quit SolidWorks first. To just open SolidWorks, quit this installer and open SolidWorks (Wine) from Applications." 'Delete and Reinstall' 'Reinstall SolidWorks?'
else
  installer_message "$welcome" 'Start' 'Welcome'
fi

installer_stage launcher 'opening Chrome'
dashboard="$(installer_ask_dashboard)"
: > "$ROOT/logs/dashboard-browser.log"
open_browser
installer_stage launcher 'waiting for the Launcher download'
msi="$(installer_choose_msi)"
mkdir -p "$CACHE/installers"
destination="$CACHE/installers/3DEXPERIENCELauncher.msi"
if [[ "${msi:A}" != "${destination:A}" ]]; then cp "$msi" "$destination"; fi

if [[ -e "$WINEPREFIX" ]]; then
  installer_stage wine 'removing the previous install'
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
installer_notify 'You can leave this running.'
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
installer_stage components 'installing graphics support'
"$ROOT/scripts/install-dxmt.sh"
installer_stage components 'building sign-in tools'
"$ROOT/scripts/build-signin-tools.sh"
if [[ ! -f "$shortcut" ]]; then
  # The dashboard's Install button hands off to the Launcher, a Wine service. Earlier steps
  # stop Wine, so start its services (wineboot) before sending anyone to the dashboard.
  installer_stage start 'starting the Launcher'
  wine wineboot > "$ROOT/logs/launcher-service.log" 2>&1
  if [[ "$installer_ui" == app ]]; then
    await_solidworks_app
  else
    installer_stage solidworks 'waiting for SolidWorks to install'
    installer_message "$install_text" 'Continue' 'Install SolidWorks' "$shortcut"
    # Continuing early asks again rather than failing.
    while [[ ! -f "$shortcut" ]]; do
      installer_message "SolidWorks isn't installed yet. Finish the installer, then click Continue.

$install_text" 'Continue' 'Install SolidWorks' "$shortcut"
    done
  fi
fi
close_dashboard
installer_stage finish 'creating the Mac app'
python3 "$ROOT/scripts/tools/configure-shortcut.py" "$shortcut" "$SW_CONFIG_FILE"
"$ROOT/scripts/09-mac-launcher.sh"
if [[ "$installer_ui" == app ]]; then
  # Started apart from the window, so closing it leaves SOLIDWORKS running.
  installer_stage finish 'opening SolidWorks'
  "$ROOT/scripts/10-fresh-signin.sh" < /dev/null > "$ROOT/logs/first-launch.log" 2>&1 &!
  installer_emit finished 'SolidWorks is opening. Sign in to your SolidWorks Maker account in its window. This can take a minute.

Next time, open SolidWorks (Wine) from Applications.'
  exit 0
fi
installer_message 'Setup is done. SolidWorks opens next: sign in to your SolidWorks Maker account in its window.

Next time, open SolidWorks (Wine) from Applications.' 'Open SolidWorks'
print 'Setup is done. Next time, open SolidWorks (Wine) from Applications.'
installer_stage finish 'opening SolidWorks'
"$ROOT/scripts/10-fresh-signin.sh"
