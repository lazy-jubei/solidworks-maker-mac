#!/bin/zsh
# Install Microsoft's WebView2 runtime required by SWXDesktopLauncher.exe.
# Rendering is configured by 10-fresh-signin.sh after the Wine/token/DXMT fixes.
set -eu
source "${0:A:h}/env.sh"
INST="$CACHE/installers/MicrosoftEdgeWebview2Setup.exe"
[[ -f "$INST" ]] || curl -fL -o "$INST" "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
shasum -a 256 "$INST"

# Remove only the old per-host policy created by earlier versions of this script.
# The verified launch recipe supplies complete flags through the environment.
python3 - <<'PYCODE'
import subprocess
for hive in ('HKCU','HKLM'):
    key=hive+r'\Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments'
    subprocess.run(['wine','reg','delete',key,'/v','SWXDesktopLauncher.exe','/f'],
                   stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
PYCODE

D="$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application"
if [[ ! -d "$D" ]]; then
  cp "$INST" "$WINEPREFIX/drive_c/windows/temp/wv2setup.exe"
  ( cd "$WINEPREFIX/drive_c" && wine 'C:\windows\temp\wv2setup.exe' /silent /install ) \
      > "$ROOT/logs/05-webview2.log" 2>&1
  echo "installer rc=$?"
fi
ls "$D" 2>/dev/null
