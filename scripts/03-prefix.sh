#!/bin/zsh
# Install the runtime dependencies into the prefix. Winetricks skips verbs it has already
# recorded, but re-running hangs in `wineserver -w` once the Launcher service is installed.
# Verbs come from community reports of SolidWorks under Wine (dotnet48, vcrun,
# win10); see notes in README.md.
set -u
source "${0:A:h}/env.sh"
LOG="$ROOT/logs"; mkdir -p "$LOG" "$W_CACHE" "$XDG_CACHE_HOME"
for verb in corefonts vcrun2022 dotnet48 msxml6 win11; do
  echo "=== $verb $(date +%T)"
  winetricks -q --force "$verb" > "$LOG/winetricks-$verb.log" 2>&1
  echo "=== $verb rc=$? $(date +%T)"
  wineserver -w
done
# The installer checks these VC11 DLLs' versions and ships real copies. Wine has builtins of the
# same names that are preferred by default and carry no version resource.
for dll in msvcr110 msvcp110 atl110 vcomp110 vccorlib110; do
  wine reg add 'HKCU\Software\Wine\DllOverrides' /v "$dll" /t REG_SZ /d native,builtin /f > /dev/null 2>&1
done
cat "$WINEPREFIX/winetricks.log" 2>/dev/null
wine cmd /c ver
df -h / "$VOL"
