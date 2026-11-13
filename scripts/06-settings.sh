#!/bin/zsh
# Display and crash settings. Safe to re-run on a prefix with the Launcher installed, unlike
# 03-prefix.sh, whose `wineserver -w` never returns once that service exists.
set -eu
source "${0:A:h}/env.sh"
# winedbg hangs under Rosetta, leaving its crash dialog stuck with a Close button that doesn't respond.
wine reg add 'HKCU\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f
# Retina: draw at the display's real pixels, with the UI scaled to match. Slower than non-Retina.
wine reg add 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /t REG_SZ /d y /f
wine reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d 192 /f
# Wine doesn't treat Command as Ctrl by default, so Command-V doesn't paste. Left Option stays available as Alt.
for key in LeftCommandIsCtrl RightCommandIsCtrl LeftOptionIsAlt; do
  wine reg add 'HKCU\Software\Wine\Mac Driver' /v "$key" /t REG_SZ /d y /f
done
# Refusing CEF's D3D delay-load dependencies caused startup failures. Clear the old
# disabled overrides, preserving unrelated entries. Native browser-local libraries
# are selected only after deployment; install-dxmt.sh configures them after copying.
for dll in d3d11 dxgi d3d9 wined3d; do
  wine reg delete 'HKCU\Software\Wine\AppDefaults\swCefSubProc.exe\DllOverrides' /v "$dll" /f >/dev/null 2>&1 || true
done
swcef="$WINEPREFIX/drive_c/Program Files/Common Files/SOLIDWORKS Shared/swcef"
if [[ -f "$swcef/swCefSubProc.exe" && -f "$swcef/d3d11.dll" && -f "$swcef/dxgi.dll" && -f "$swcef/d3d10core.dll" ]]; then
  for dll in d3d11 dxgi d3d10core; do
    wine reg add 'HKCU\Software\Wine\AppDefaults\swCefSubProc.exe\DllOverrides' /v "$dll" /t REG_SZ /d native /f
  done
  wine reg add 'HKCU\Software\Wine\AppDefaults\swCefSubProc.exe\DllOverrides' /v winemetal /t REG_SZ /d builtin /f
fi

# The fresh install enables PLM Services; with it active, local document open/sketch
# tests crashed unless tracing changed the timing. Match the working main setup.
# This disables the optional PLM integration, not Makers account/license checks.
for hive in HKCU HKLM; do
  if [[ "$hive" == HKCU ]]; then branch='Software\SolidWorks\AddInsStartup'; else branch='Software\SolidWorks\AddIns'; fi
  wine reg add "${hive}\\${branch}\\{DD2533E5-1513-40D8-82B4-927790D0A896}" /ve /t REG_DWORD /d 0 /f
done
