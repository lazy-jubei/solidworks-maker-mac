#!/bin/zsh
# The downloaded installer offers updates before changing an existing installation.
set -eu
(( $# == 2 )) || { print -u2 'Usage: manage-existing.sh <release folder> <installed folder>'; exit 2; }
release_root="${1:A}"
export SW_PROJECT_ROOT="${2:A}"
export SW_UPDATE_SOURCE="$release_root"
source "$release_root/scripts/env.sh"
source "$release_root/scripts/tools/installer-ui.zsh"
mkdir -p "$ROOT/logs"
if [[ "$installer_ui" == window ]]; then
  if installer_open_window; then exit 0; fi
  installer_ui=dialogs
fi
stage='choosing an update'
trap 'rc=$?; if (( rc != 0 && rc != 130 )); then installer_failed "$stage"; fi' EXIT
choice="$(installer_existing_choice)"
installer_stage components 'updating scripts and the Mac shortcut'
lock="$ROOT/.sw-update-lock"
mkdir "$lock" 2>/dev/null || { print -u2 'Another update is running.'; exit 1; }
trap 'rc=$?; rmdir "$lock"; if (( rc != 0 && rc != 130 )); then installer_failed "$stage"; fi' EXIT
python3 "$release_root/scripts/tools/update-project.py" "$release_root" "$ROOT"
zsh "$ROOT/scripts/09-mac-launcher.sh"
rmdir "$lock"
trap 'rc=$?; if (( rc != 0 && rc != 130 )); then installer_failed "$stage"; fi' EXIT
if [[ "$choice" == reinstall ]]; then
  # The regular installer retains its separate destructive confirmation.
  unset SW_UPDATE_SOURCE
  export SW_INSTALLER_REINSTALL=1
  exec zsh "$ROOT/scripts/install-guided.sh"
fi
if [[ "$choice" == update-wine ]]; then
  installer_stage components 'updating Wine patches and graphics'
  zsh "$ROOT/scripts/update-wine.sh"
fi
installer_stage finish 'update complete'
if [[ "$installer_ui" == app ]]; then
  installer_emit finished 'Update complete. Your SOLIDWORKS installation, settings and CAD files were kept. Open SolidWorks (Wine) from Applications.'
else
  installer_message 'Update complete. Open SolidWorks (Wine) from Applications.' 'Close'
fi
