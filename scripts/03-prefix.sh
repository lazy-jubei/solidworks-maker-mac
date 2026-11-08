#!/bin/zsh
# Install the runtime dependencies into a new prefix. Winetricks skips verbs it has already
# recorded, but re-running hangs in `wineserver -w` once the Launcher service is installed.
# Verbs come from community reports of SolidWorks under Wine (dotnet48, vcrun,
# win10); see notes in README.md.
# Two lanes run at once: the fonts (plain files and registry entries) beside the installers,
# which use Windows Installer and so must run one after another. win11 runs last because the
# .NET installer changes the Windows version.
set -eu
source "${0:A:h}/env.sh"
LOG="$ROOT/logs"; mkdir -p "$LOG" "$W_CACHE" "$XDG_CACHE_HOME"
run_verb() {
  local verb="$1" verb_result
  echo "=== $verb $(date +%T)"
  if winetricks -q --force "$verb" > "$LOG/winetricks-$verb.log" 2>&1; then
    echo "=== $verb rc=0 $(date +%T)"
  else
    verb_result=$?
    print -u2 "Dependency $verb failed; see $LOG/winetricks-$verb.log"
    return "$verb_result"
  fi
}
# Create the prefix once, so the lanes don't both initialise it.
echo "=== create prefix $(date +%T)"
wine wineboot -i > "$LOG/prefix-create.log" 2>&1
wineserver -w
fonts_pid=''
trap 'rc=$?; if [[ -n "$fonts_pid" ]]; then kill "$fonts_pid" 2>/dev/null || true; fi; exit $rc' EXIT
run_verb corefonts &
fonts_pid=$!
for verb in vcrun2022 dotnet48 msxml6; do
  run_verb "$verb"
done
wait "$fonts_pid" || exit $?
fonts_pid=''
wineserver -w
run_verb win11
wineserver -w
# The installer checks these VC11 DLLs' versions and ships real copies. Wine has builtins of the
# same names that are preferred by default and carry no version resource.
for dll in msvcr110 msvcp110 atl110 vcomp110 vccorlib110; do
  wine reg add 'HKCU\Software\Wine\DllOverrides' /v "$dll" /t REG_SZ /d native,builtin /f > /dev/null 2>&1
done
if [[ -f "$WINEPREFIX/winetricks.log" ]]; then cat "$WINEPREFIX/winetricks.log"; fi
wine cmd /c ver
df -h / "$VOL"
