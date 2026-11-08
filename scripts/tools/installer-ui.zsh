# Guided-installer prompts. Source this from install-guided.sh.
# Uses macOS's own AppleScript dialogs (nothing to download or sign) when a desktop session
# is available; SW_INSTALLER_UI=terminal, or no desktop session, falls back to Terminal prompts.
# Values are passed to osascript as arguments, never pasted into AppleScript source.

SW_MAKERS_URL="${SW_MAKERS_URL:-https://www.solidworks.com/maker-cloud}"
installer_title='SOLIDWORKS Maker on Mac'
case "${SW_INSTALLER_UI:-auto}" in
  terminal) installer_gui=0 ;;
  dialogs) installer_gui=1 ;;
  *)
    installer_gui=0
    if command -v osascript >/dev/null && [[ -z "${SSH_CONNECTION:-}" ]] \
       && [[ "$(launchctl managername 2>/dev/null || true)" == Aqua ]]; then
      installer_gui=1
    fi ;;
esac

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

# installer_message <text> [button]: an information screen with one button (and Quit).
installer_message() {
  if (( installer_gui )); then
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
  if (( installer_gui )); then
    installer_osascript 'on run argv
  display notification (item 1 of argv) with title (item 2 of argv)
end run' "$1" "$installer_title" >/dev/null || true
  fi
}

# installer_ask_dashboard: prints the URL to open in the Windows-identifying browser.
installer_ask_dashboard() {
  local text='Next, a browser opens so you can download the 3DEXPERIENCE Launcher:
sign in to SOLIDWORKS for Makers, then download the Launcher from your dashboard.

Keep this address to start at SOLIDWORKS Maker Cloud, or paste your own Makers dashboard URL.'
  local url
  if (( installer_gui )); then
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
  local text='Download the 3DEXPERIENCE Launcher in the browser that just opened:
sign in, then download the Launcher from your Makers dashboard.

When the download has finished, click Continue.'
  local msi
  if (( installer_gui )); then
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
  if (( installer_gui )); then
    installer_osascript '
on run argv
  display alert (item 1 of argv) message (item 2 of argv) as critical buttons {"OK"} default button 1
end run' "Setup stopped during: $1" 'The Terminal window shows the details. Fix the problem, then run the same command again: completed steps are skipped.' >/dev/null || true
  fi
}
