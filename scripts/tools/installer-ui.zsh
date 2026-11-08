# Guided-installer prompts. Source this from install-guided.sh.
# In a desktop session the installer opens its own window (InstallerApp.swift, compiled
# here with the Command Line Tools, so nothing is downloaded or needs signing) and runs
# inside it with SW_INSTALLER_UI=app. If the window can't be built, macOS's AppleScript
# dialogs are used; SW_INSTALLER_UI=terminal, or no desktop session, uses Terminal prompts.
# Values are passed to osascript as arguments, never pasted into AppleScript source.

SW_MAKERS_URL="${SW_MAKERS_URL:-https://www.solidworks.com/maker-cloud}"
installer_title='SOLIDWORKS Maker on Mac'
installer_ui_dir="${${(%):-%x}:A:h}"
installer_window_app="${SW_TOOLS:-$ROOT/tools}/SOLIDWORKS Maker Installer.app"
case "${SW_INSTALLER_UI:-auto}" in
  terminal|dialogs|app|window) installer_ui="$SW_INSTALLER_UI" ;;
  *)
    installer_ui=terminal
    if command -v osascript >/dev/null && [[ -z "${SSH_CONNECTION:-}" ]] \
       && [[ "$(launchctl managername 2>/dev/null || true)" == Aqua ]]; then
      installer_ui=window
    fi ;;
esac
installer_gui=0
[[ "$installer_ui" == (dialogs|window) ]] && installer_gui=1

# installer_open_window: build the installer window if needed and open it. Fails (so the
# caller falls back to dialogs) when it can't be built.
installer_open_window() {
  local src="$installer_ui_dir/InstallerApp.swift" app="$installer_window_app"
  local bin="$app/Contents/MacOS/SOLIDWORKS Maker Installer" log="$ROOT/logs/installer-window-build.log"
  if [[ ! -x "$bin" || "$src" -nt "$bin" ]]; then
    if ! xcrun --find swiftc >/dev/null 2>&1; then
      xcode-select --install 2>/dev/null || true
      print 'Complete the Command Line Tools installation in the macOS window.'
      read -r '?Press Return when installation has finished: '
      xcrun --find swiftc >/dev/null 2>&1 || return 1
    fi
    print 'Preparing the installer window…'
    rm -rf -- "$app"
    mkdir -p "$app/Contents/MacOS" "${log:h}"
    cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>SOLIDWORKS Maker Installer</string>
  <key>CFBundleIdentifier</key><string>io.github.lazy-jubei.solidworks-maker-installer</string>
  <key>CFBundleName</key><string>SOLIDWORKS Maker Installer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
    if ! xcrun swiftc -Onone -parse-as-library -target "$(uname -m)-apple-macos13" -o "$bin" "$src" > "$log" 2>&1; then
      rm -rf -- "$app"
      print -u2 "The installer window could not be built (see $log); using dialogs instead."
      return 1
    fi
    codesign --force --sign - "$app" >/dev/null 2>&1 || true
  fi
  open "$app" --args --root "$ROOT"
}

# App mode: messages to the window are tab-separated lines on stderr starting with @@sw
# (stdout is often captured by $(...)); answers come back one line at a time on stdin.
installer_emit() {
  local field out=()
  for field in "$@"; do
    field="${field//\\/\\\\}"
    field="${field//$'\t'/\\t}"
    out+=("${field//$'\n'/\\n}")
  done
  print -u2 -r -- "@@sw"$'\t'"${(pj:\t:)out}"
}

installer_app_read() {
  local reply
  IFS= read -r reply || reply='@@quit'
  if [[ "$reply" == '@@quit' ]]; then
    print -u2 'Installation stopped. Open the installer again to continue where you left off.'
    exit 130
  fi
  print -r -- "$reply"
}

# installer_stage <step> <text>: record the current stage (named in failure messages).
# Steps: wine, launcher, components, solidworks, finish.
installer_stage() {
  stage="$2"
  if [[ "$installer_ui" == app ]]; then installer_emit stage "$1" "$2"; fi
}

# Run an AppleScript; "User canceled" (Quit or Escape) ends the installer cleanly.
installer_osascript() {
  local script="$1" result
  shift
  if ! result="$(osascript -e "$script" -- "$@" 2>&1)"; then
    if [[ "$result" == *'(-128)'* ]]; then
      print -u2 'Installation stopped. Run the same command again to continue where you left off.'
      exit 130
    fi
    print -u2 -r -- "$result"
    return 1
  fi
  print -r -- "$result"
}

# installer_message <text> [button] [title] [file]: an information screen with one button (and
# Quit). With a file, the window keeps the button disabled until that file exists.
installer_message() {
  if [[ "$installer_ui" == app ]]; then
    installer_emit message "${2:-Continue}" "${3:-}" "$1" "${4:-}"
    installer_app_read >/dev/null
  elif (( installer_gui )); then
    installer_osascript '
on run argv
  display dialog (item 1 of argv) with title (item 3 of argv) buttons {"Quit", item 2 of argv} default button 2 cancel button 1 with icon note
end run' "$1" "${2:-Continue}" "$installer_title" >/dev/null
  else
    print -r -- "$1"
    read -r "?Press Return to continue: "
  fi
}

# installer_notify <text>: a passing status note while a long step runs.
installer_notify() {
  print -r -- "$1"
  if [[ "$installer_ui" == app ]]; then
    installer_emit notify "$1"
  elif (( installer_gui )); then
    installer_osascript 'on run argv
  display notification (item 1 of argv) with title (item 2 of argv)
end run' "$1" "$installer_title" >/dev/null || true
  fi
}

# installer_ask_dashboard: prints the URL to open in the Windows-identifying browser.
installer_ask_dashboard() {
  local text='Next, a separate browser opens so you can download the 3DEXPERIENCE Launcher: sign in to SOLIDWORKS for Makers, then download the Launcher from your dashboard.

Keep this address to start at SOLIDWORKS Maker Cloud, or paste your own Makers dashboard URL.'
  local url
  if [[ "$installer_ui" == app ]]; then
    installer_emit url "$SW_MAKERS_URL" "$text"
    url="$(installer_app_read)"
  elif (( installer_gui )); then
    url="$(installer_osascript '
on run argv
  set reply to display dialog (item 1 of argv) with title (item 3 of argv) default answer (item 2 of argv) buttons {"Quit", "Open Browser"} default button 2 cancel button 1 with icon note
  return text returned of reply
end run' "$text" "$SW_MAKERS_URL" "$installer_title")"
  else
    print -u2 -r -- "$text"
    read -r "url?URL [$SW_MAKERS_URL]: "
  fi
  url="${${url##[[:space:]]#}%%[[:space:]]#}"
  [[ -n "$url" ]] || url="$SW_MAKERS_URL"
  [[ "$url" == https://* ]] || { print -u2 'Use an HTTPS address from SOLIDWORKS or your Makers account.'; return 1; }
  print -r -- "$url"
}

# installer_choose_msi: prints the path of the downloaded Launcher MSI. The field starts at
# the browser's usual download location; Browse… opens a file picker in Downloads.
installer_choose_msi() {
  local default="${SW_LAUNCHER_MSI:-$HOME/Downloads/3DEXPERIENCELauncher.msi}"
  local text='Download the 3DEXPERIENCE Launcher in the browser that just opened: sign in, then download the Launcher from your Makers dashboard.

When the download has finished, click Continue.'
  local msi
  if [[ "$installer_ui" == app ]]; then
    installer_emit msi "$default" "$text"
    msi="$(installer_app_read)"
  elif (( installer_gui )); then
    # Loops until the path names an existing file, so an unfinished download is not an error.
    msi="$(installer_osascript '
on run argv
  set intro to item 1 of argv
  set chosen to item 2 of argv
  set prompt to intro
  repeat
    set reply to display dialog prompt with title (item 3 of argv) default answer chosen buttons {"Quit", "Browse…", "Continue"} default button 3 cancel button 1 with icon note
    set chosen to text returned of reply
    if button returned of reply is "Browse…" then
      try
        set chosen to POSIX path of (choose file with prompt "Select the 3DEXPERIENCE Launcher installer (.msi)" default location (path to downloads folder))
      end try
      set prompt to intro
    else
      try
        set found to (POSIX file chosen) as alias
        return chosen
      on error
        set prompt to "No file was found at this path yet. Wait for the download to finish, or click Browse… to find it." & return & return & intro
      end try
    end if
  end repeat
end run' "$text" "$default" "$installer_title")"
  else
    print -u2 -r -- "$text"
    read -r "msi?Launcher MSI path [$default]: "
    msi="${(Q)msi}"
    [[ -n "$msi" ]] || msi="$default"
  fi
  [[ -f "$msi" && "${msi:e:l}" == msi ]] || { print -u2 "That is not an .msi file: $msi"; return 1; }
  print -r -- "$msi"
}

# installer_failed <stage>: tell the user in a dialog when a step stops the installer.
installer_failed() {
  print -u2 -r -- "Setup stopped during: $1"
  if [[ "$installer_ui" == app ]]; then
    installer_emit failed "$1"
  elif (( installer_gui )); then
    installer_osascript '
on run argv
  display alert (item 1 of argv) message (item 2 of argv) as critical buttons {"OK"} default button 1
end run' "Setup stopped during: $1" 'The Terminal window shows the details. Fix the problem, then run the same command again: completed steps are skipped.' >/dev/null || true
  fi
}
