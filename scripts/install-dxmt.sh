#!/bin/zsh
# Install DXMT app-local for WebView2 and for the SOLIDWORKS CEF Task Pane subprocesses
# (swCefSubProc.exe), preserving CAD's original D3D11/DXGI libraries.
# Close the selected prefix before running; this script starts it to set overrides.
set -eu
(( $# <= 1 )) || { print -u2 'usage: install-dxmt.sh [--webview-only]'; exit 2; }
case "${1:-}" in
  '') scope=all ;;
  --webview-only) scope=webview ;;
  *) print -u2 'usage: install-dxmt.sh [--webview-only]'; exit 2 ;;
esac
source "${0:A:h}/env.sh"
python3 - "$WINE_APP/Contents/Resources/wine/bin/wineserver" <<'PY'
import os,subprocess,sys
wanted=os.path.realpath(sys.argv[1])
for line in subprocess.check_output(['ps','-axo','comm='],text=True).splitlines():
    if os.path.basename(line.strip())=='wineserver' and os.path.realpath(line.strip())==wanted:
        sys.exit('Wine server is running. Close this prefix before replacing graphics DLLs.')
PY
mkdir -p "$CACHE/dxmt"
ARCHIVE="$CACHE/dxmt/dxmt-v0.80-builtin.tar.gz"
[[ -f "$ARCHIVE" ]] || curl --proto '=https' -fL -o "$ARCHIVE" https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz
print "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d  $ARCHIVE" | shasum -a 256 -c -
# The archive already holds a top-level v0.80/ folder.
rm -rf "$CACHE/dxmt/v0.80"
tar -xzf "$ARCHIVE" -C "$CACHE/dxmt"
python3 - "$CACHE/dxmt/v0.80" "$WINE_APP/Contents/Resources/wine/lib/wine" "$WINEPREFIX" "$scope" <<'PY'
from pathlib import Path
import hashlib,shutil,sys
src,lib,prefix=map(Path,sys.argv[1:4])
include_cef = sys.argv[4] == "all"
def patched(name):
    data=bytearray((src/'x86_64-windows'/name).read_bytes())
    if data[64:81]!=b'Wine builtin DLL\0':sys.exit('Unexpected DXMT PE header')
    # One byte of Wine's loader marker only. This makes app-local native loading
    # possible instead of redirecting back to the global builtin. Code unchanged.
    data[64]=ord('X')
    return bytes(data)
# Preflight every target before replacing anything, so a missing component can never leave
# WebView2 or the global libraries half-installed.
versions=prefix/'drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application'
candidates=[p for p in versions.iterdir() if (p/'msedgewebview2.exe').is_file()] if versions.is_dir() else []
if not candidates:sys.exit('Install WebView2 first (05-webview2.sh)')
edge=max(candidates,key=lambda p:tuple(int(n) for n in p.name.split('.')))
swcef=prefix/'drive_c/Program Files/Common Files/SOLIDWORKS Shared/swcef'
if include_cef and not (swcef/'swCefSubProc.exe').is_file():
    sys.exit('swCefSubProc.exe not found in '+str(swcef)+' - install SOLIDWORKS before installing DXMT')
blobs={name:patched(name) for name in ('d3d11.dll','dxgi.dll','d3d10core.dll')}
for name,data in blobs.items():
    # Restore the known pre-experiment originals if global DXMT was installed.
    for folder in (lib/'x86_64-windows',prefix/'drive_c/windows/system32'):
        dst=folder/name;backup=dst.with_name(name+'.before-dxmt')
        if backup.exists():
            tmp=dst.with_name(name+'.new');shutil.copy2(backup,tmp);tmp.replace(dst)
    dst=edge/name;backup=dst.with_name(name+'.before-scoped-dxmt')
    if dst.exists() and dst.read_bytes()!=data and not backup.exists():shutil.copy2(dst,backup)
    tmp=dst.with_name(name+'.new');tmp.write_bytes(data);tmp.replace(dst)
    print('webview2',name,hashlib.sha256(data).hexdigest())
    # Deploy CEF dependencies after the vendor installation. A loaded module
    # identifies the selected file; the browser may still choose a software GPU.
    if include_cef:
        dst=swcef/name;backup=dst.with_name(name+'.before-scoped-dxmt')
        if dst.exists() and dst.read_bytes()!=data and not backup.exists():shutil.copy2(dst,backup)
        tmp=dst.with_name(name+'.new');tmp.write_bytes(data);tmp.replace(dst)
        print('swcef',name,hashlib.sha256(data).hexdigest())
# Only winemetal has a Unix companion; it stays a Wine builtin and is imported
# by browser-local DXMT. Normal CAD D3D11/DXGI do not import it.
for dst in (lib/'x86_64-windows/winemetal.dll',prefix/'drive_c/windows/system32/winemetal.dll'):
    tmp=dst.with_name(dst.name+'.new');shutil.copy2(src/'x86_64-windows/winemetal.dll',tmp);tmp.replace(dst)
shutil.copy2(src/'x86_64-unix/winemetal.so',lib/'x86_64-unix/winemetal.so')
print('Browser-local DXMT installed in',edge)
if include_cef: print('CEF dependencies installed in',swcef)
PY
python3 - "$scope" <<'PY'
import subprocess,sys
apps=['msedgewebview2.exe']
if sys.argv[1] == 'all': apps.append('swCefSubProc.exe')
for app in apps:
    key=rf'HKCU\Software\Wine\AppDefaults\{app}\DllOverrides'
    for name,value in (('d3d11','native'),('dxgi','native'),('d3d10core','native'),('winemetal','builtin')):
        subprocess.run(['wine','reg','add',key,'/v',name,'/t','REG_SZ','/d',value,'/f'],check=True,stdout=subprocess.DEVNULL)
PY
if [[ "$scope" == all ]]; then
  print 'DXMT v0.80 is scoped to WebView2 and the SOLIDWORKS CEF subprocesses; CAD graphics remain original.'
else
  print 'WebView2 graphics support installed.'
fi
