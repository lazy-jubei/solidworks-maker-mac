#!/bin/zsh
# Build/install the opt-in, CAD-only confirmation button experiment.
set -eu
source "${0:A:h}/env.sh"
BUILD="${SW_BUILD:-$VOL/build}"
SRC="$BUILD/src-wine-$WINE_VERSION"
OBJ="$BUILD/obj-wine-$WINE_VERSION"
python3 - "$WINE_APP/Contents/Resources/wine/bin/wineserver" <<'PY'
import os,subprocess,sys
wanted=os.path.realpath(sys.argv[1])
for command in subprocess.check_output(['ps','-axo','comm='],text=True).splitlines():
    if os.path.basename(command.strip())=='wineserver' and os.path.realpath(command.strip())==wanted:
        sys.exit('Close and stop the selected Wine prefix before installing its control DLL.')
PY
python3 "${0:A:h}/patches/comctl32-button-capture.py" "$SRC"
# Keep PropertyManager headings from shrinking during repeated paint calls.
grep -q sw_keep_heading_width "$SRC/dlls/comctl32_v6/button.c" \
  || patch -s -N -d "$SRC" -p1 < "${0:A:h}/patches/comctl32-property-manager-layout.patch"
export PATH="$(sw_build_path "$BUILD/llvm-mingw/bin")"
mkdir -p "$ROOT/logs"
arch -x86_64 make -C "$OBJ" -j8 dlls/comctl32_v6/x86_64-windows/comctl32_v6.dll > "$ROOT/logs/button-capture-build.log" 2>&1
python3 - "$OBJ/dlls/comctl32_v6/x86_64-windows/comctl32_v6.dll" "$WINE_APP/Contents/Resources/wine/lib/wine/x86_64-windows/comctl32_v6.dll" "$WINEPREFIX/drive_c/windows/system32/comctl32_v6.dll" <<'PY'
from pathlib import Path
import hashlib,shutil,sys
src=Path(sys.argv[1])
for target in map(Path,sys.argv[2:]):
    backup=target.with_name(target.name+'.before-button-capture')
    if not backup.exists():shutil.copy2(target,backup)
    tmp=target.with_name(target.name+'.new');shutil.copy2(src,tmp);tmp.replace(target)
    print(target.name,hashlib.sha256(target.read_bytes()).hexdigest())
PY
python3 "${0:A:h}/patches/mark-button-capture.py" "$WINE_APP/Contents/Resources/wine/lib/wine/x86_64-windows/comctl32_v6.dll" "$WINEPREFIX/drive_c/windows/system32/comctl32_v6.dll"
print 'Installed and marked the scoped SolidWorks confirmation button guard.'
