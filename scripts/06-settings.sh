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
# Chromium's GPU process spins on wined3d (about 5,400 SetPixelFormat calls a second), so it gets no Direct3D.
for dll in d3d11 dxgi d3d9 wined3d; do
  wine reg add 'HKCU\Software\Wine\AppDefaults\swCefSubProc.exe\DllOverrides' /v "$dll" /t REG_SZ /d '' /f
done

# The fresh install enables PLM Services; with it active, local document open/sketch
# tests crashed unless tracing changed the timing. Match the working main setup.
# This disables the optional PLM integration, not Makers account/license checks.
for hive in HKCU HKLM; do
  if [[ "$hive" == HKCU ]]; then branch='Software\SolidWorks\AddInsStartup'; else branch='Software\SolidWorks\AddIns'; fi
  wine reg add "${hive}\\${branch}\\{DD2533E5-1513-40D8-82B4-927790D0A896}" /ve /t REG_DWORD /d 0 /f
done
