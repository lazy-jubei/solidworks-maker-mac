#!/usr/bin/env python3
"""Verify the patched Wine modules that a launcher run depends on.

Each fix gated behind an exact hash or an environment flag only works while the installed binaries
still match what the builder produced. A Wine or prefix update replaces one half of a pair and the
fix disappears with no error, so this checks the pair, the saved original, and any marker file.

Run from scripts/update-wine.sh, which has a real install to inspect. It is deliberately not in
check-release.py, whose sandbox has no installed Wine to verify.
"""
from pathlib import Path
import hashlib,os,sys

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

root=Path(__file__).resolve().parent.parent
# Path('') is Path('.'), so an unset variable must be caught as a string: otherwise every module
# resolves against the working directory and the check reports failures for an install that is fine.
wine_value=os.environ.get('WINE_APP','').strip()
prefix_value=os.environ.get('WINEPREFIX','').strip()
if not wine_value or not prefix_value:
    sys.exit('set WINE_APP and WINEPREFIX (source scripts/env.sh)')
wine=Path(wine_value)
prefix=Path(prefix_value)
if not wine.is_dir() or not prefix.is_dir():
    sys.exit('WINE_APP and WINEPREFIX must both point at an existing directory')

lib=wine/'Contents/Resources/wine/lib/wine'
system32=prefix/'drive_c/windows/system32'
# name: (unix or PE location in the bundle, prefix copy or None, marker suffix or None)
modules={'winemac.so':(lib/'x86_64-unix/winemac.so',None,'.gdi.sha256'),
         'opengl32.so':(lib/'x86_64-unix/opengl32.so',None,None),
         'win32u.so':(lib/'x86_64-unix/win32u.so',None,None),
         'comctl32_v6.dll':(lib/'x86_64-windows/comctl32_v6.dll',system32/'comctl32_v6.dll','.capture.sha256'),
         'gdi32.dll':(lib/'x86_64-windows/gdi32.dll',system32/'gdi32.dll',None),
         'wmiutils.dll':(lib/'x86_64-windows/wmiutils.dll',system32/'wbem/wmiutils.dll',None)}
# winemac.so is restored by rebuilding from an unpatched tree, so its safety net is the marker
# below rather than a saved binary; every other module must keep one.
no_stock={'winemac.so'}
bad=[]
for name,(bundle,copy,marker) in modules.items():
    if not bundle.is_file():
        bad.append(f'{name}: missing {bundle}');continue
    if copy is not None:
        if not copy.is_file():bad.append(f'{name}: prefix copy missing {copy}')
        elif sha(bundle)!=sha(copy):bad.append(f'{name}: bundle and prefix differ')
    if marker and bundle.with_name(bundle.name+marker).is_file():
        expected=bundle.with_name(bundle.name+marker).read_text().strip()
        if sha(bundle)!=expected:bad.append(f'{name}: marker no longer matches, gated fix is off')
    stock=bundle.with_name(bundle.name+'.stock')
    if name not in no_stock and not stock.is_file():bad.append(f'{name}: no {stock.name}, cannot restore the original')
for line in bad:print('FAIL',line)
print('ok' if not bad else f'{len(bad)} problem(s)')
sys.exit(1 if bad else 0)
