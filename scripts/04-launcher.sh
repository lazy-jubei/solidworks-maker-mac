#!/bin/zsh
# Install the 3DEXPERIENCE Launcher into the prefix.
# The MSI comes from the platform dashboard (see README) and is kept in cache/installers.
set -u
source "${0:A:h}/env.sh"
MSI="$CACHE/installers/3DEXPERIENCELauncher.msi"
LOG="$ROOT/logs"; mkdir -p "$LOG"
cp "$MSI" "$WINEPREFIX/drive_c/windows/temp/launcher.msi"
WINEDEBUG="-all,err+all" wine msiexec /i 'C:\windows\temp\launcher.msi' /qn '/l*v' 'C:\windows\temp\launcher-msi.log' > "$LOG/04-launcher.log" 2>&1
echo "msiexec rc=$?"
iconv -f UTF-16LE -t UTF-8 "$WINEPREFIX/drive_c/windows/temp/launcher-msi.log" > "$LOG/launcher-msi.log" 2>/dev/null \
  || cp "$WINEPREFIX/drive_c/windows/temp/launcher-msi.log" "$LOG/launcher-msi.log"

# Run the service on the visible desktop. By default Wine puts services on a hidden
# window station, so the Launcher's trust prompt and SolidWorks installer windows would
# never appear. 0x110 = SERVICE_WIN32_OWN_PROCESS | SERVICE_INTERACTIVE_PROCESS.
wine reg add 'HKLM\System\CurrentControlSet\Services\3DEXPERIENCELauncher' /v Type /t REG_DWORD /d 0x110 /f
wineserver -k
wineserver -w
wine wineboot > /dev/null 2>&1   # starts auto-start services, including the Launcher
