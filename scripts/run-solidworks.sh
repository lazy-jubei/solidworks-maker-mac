#!/bin/zsh
# Start SolidWorks with the same command as the platform's desktop shortcut. SLDWORKS.exe refuses
# to run on its own ("must be launched from the 3DEXPERIENCE Platform").
# Mount the image first (01-storage.sh). TENANT and REGISTRY come from your own shortcut:
# C:\users\Public\Desktop\SOLIDWORKS Design.lnk
set -u
source "${0:A:h}/env.sh"
# Set this inside the script: macOS strips DYLD_* variables when starting /bin/zsh.
# Select the X11 driver separately and restart the prefix before using this option.
if [[ "${SW_GRAPHICS:-mac}" == x11 ]]; then
  export DYLD_FALLBACK_LIBRARY_PATH="/opt/X11/lib:/usr/lib"
fi
# Report x64 emulation on an ARM64 host on every Mac. The license loader's native-x64 path
# crashes under Wine ("cannot load JS0PCC.dll", then a null call), on Intel Macs as well;
# its x64-on-ARM64 path, which Windows on ARM also takes, starts normally.
export SW_REPORT_ARM64=1
TENANT="${SW_TENANT:?Set SW_TENANT in config.local.zsh from your own SOLIDWORKS shortcut}"
REGISTRY="${SW_REGISTRY:-https://eu1-makers-registry.3dexperience.3ds.com}"
W='C:\Program Files\Dassault Systemes\SOLIDWORKS 3DEXPERIENCE R2026x\win_b64\code\bin'
LOG_DIR="${SW_LOG_DIR:-$ROOT/logs}"
mkdir -p "$LOG_DIR"
cd "$WINEPREFIX/drive_c"
# The Launcher service can exit at boot with "Core function failed!", but starts fine afterwards.
if ! curl -s -m 3 -o /dev/null "http://127.0.0.1:20250/iframe?version=1.0&id=health"; then
  wine wineboot > /dev/null 2>&1
  wine net start 3DEXPERIENCELauncher > /dev/null 2>&1
fi
# Only opt into GDI presentation when this exact driver was installed by our builder.
# A later Wine update invalidates the marker and leaves normal rendering enabled.
GL_DRIVER="$WINE_APP/Contents/Resources/wine/lib/wine/x86_64-unix/winemac.so"
if [[ -f "$GL_DRIVER.gdi.sha256" ]]; then
  expected="$(<"$GL_DRIVER.gdi.sha256")"
  actual="$(shasum -a 256 "$GL_DRIVER" | cut -d ' ' -f 1)"
  if [[ "$actual" == "$expected" ]]; then export SW_OPENGL_GDI="${SW_OPENGL_GDI:-1}"; fi
fi
# Only enable the scoped button guard for the exact matching library/prefix pair.
BUTTON_DLL="$WINE_APP/Contents/Resources/wine/lib/wine/x86_64-windows/comctl32_v6.dll"
if [[ -f "$BUTTON_DLL.capture.sha256" && -f "$WINEPREFIX/drive_c/windows/system32/comctl32_v6.dll" ]]; then
  expected="$(<"$BUTTON_DLL.capture.sha256")"
  actual="$(shasum -a 256 "$BUTTON_DLL" | cut -d ' ' -f 1)"
  prefix_actual="$(shasum -a 256 "$WINEPREFIX/drive_c/windows/system32/comctl32_v6.dll" | cut -d ' ' -f 1)"
  if [[ "$actual" == "$expected" && "$prefix_actual" == "$expected" ]]; then
    export SW_BUTTON_CAPTURE_GUARD="${SW_BUTTON_CAPTURE_GUARD:-1}"
  fi
fi
# Automatic cross-process viewport resizing is disabled: it caused sketch crashes.
# Keep CAD's own geometry untouched. SwViewportFix is retained only for diagnosis.

exec wine "$W\\CATSTART.exe" -run "SWXDesktopLauncher.exe" \
    -object "--AppName=\"SWXCSWK_AP\" -tenant=$TENANT  -monoapp -3DRegistryURL=$REGISTRY" -nowindow \
    > "$LOG_DIR/solidworks-run.log" 2>&1
