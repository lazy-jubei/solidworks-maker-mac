#!/bin/zsh
# Install DXMT only for WebView2, preserving CAD's original D3D11/DXGI libraries.
# Close the selected prefix before running; this script starts it to set overrides.
set -eu
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
python3 - "$CACHE/dxmt/v0.80" "$WINE_APP/Contents/Resources/wine/lib/wine" "$WINEPREFIX" <<'PY'
from pathlib import Path
import hashlib,shutil,sys
src,lib,prefix=map(Path,sys.argv[1:])
versions=prefix/'drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application'
candidates=[p for p in versions.iterdir() if (p/'msedgewebview2.exe').is_file()]
if not candidates:sys.exit('Install WebView2 first (05-webview2.sh)')
edge=max(candidates,key=lambda p:tuple(int(n) for n in p.name.split('.')))
for name in ('d3d11.dll','dxgi.dll','d3d10core.dll'):
    # Restore the known pre-experiment originals if global DXMT was installed.
    for folder in (lib/'x86_64-windows',prefix/'drive_c/windows/system32'):
        dst=folder/name;backup=dst.with_name(name+'.before-dxmt')
        if backup.exists():
            tmp=dst.with_name(name+'.new');shutil.copy2(backup,tmp);tmp.replace(dst)
    data=bytearray((src/'x86_64-windows'/name).read_bytes())
    if data[64:81]!=b'Wine builtin DLL\0':sys.exit('Unexpected DXMT PE header')
    # One byte of Wine's loader marker only. This makes app-local native loading
    # possible instead of redirecting back to the global builtin. Code unchanged.
    data[64]=ord('X')
    dst=edge/name;backup=dst.with_name(name+'.before-scoped-dxmt')
    if dst.exists() and dst.read_bytes()!=data and not backup.exists():shutil.copy2(dst,backup)
    tmp=dst.with_name(name+'.new');tmp.write_bytes(data);tmp.replace(dst)
    print(name,hashlib.sha256(data).hexdigest())
# Only winemetal has a Unix companion; it stays a Wine builtin and is imported
# by browser-local DXMT. Normal CAD D3D11/DXGI do not import it.
for dst in (lib/'x86_64-windows/winemetal.dll',prefix/'drive_c/windows/system32/winemetal.dll'):
    tmp=dst.with_name(dst.name+'.new');shutil.copy2(src/'x86_64-windows/winemetal.dll',tmp);tmp.replace(dst)
shutil.copy2(src/'x86_64-unix/winemetal.so',lib/'x86_64-unix/winemetal.so')
print('Browser-local DXMT installed in',edge)
PY
python3 - <<'PY'
import subprocess
key=r'HKCU\Software\Wine\AppDefaults\msedgewebview2.exe\DllOverrides'
for name in ('d3d11','dxgi','d3d10core'):
    subprocess.run(['wine','reg','add',key,'/v',name,'/t','REG_SZ','/d','native','/f'],check=True,stdout=subprocess.DEVNULL)
subprocess.run(['wine','reg','add',key,'/v','winemetal','/t','REG_SZ','/d','builtin','/f'],check=True,stdout=subprocess.DEVNULL)
PY
print 'DXMT v0.80 is scoped to WebView2; CAD graphics remain original.'
