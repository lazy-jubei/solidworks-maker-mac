#!/bin/zsh
# Opt-in Mac OpenGL/GDI clipping workaround, tested on the separate fresh prefix.
# Stop the selected prefix before installing its driver. No vendor DLLs change.
set -eu
source "${0:A:h}/env.sh"
BUILD="${SW_BUILD:-$VOL/build}"
SRC="$BUILD/src-wine-$WINE_VERSION"
OBJ="$BUILD/obj-wine-$WINE_VERSION"
[[ -f "$OBJ/Makefile" ]] || { print -u2 'Build the Wine source with build-shell32.sh first.'; exit 1; }
python3 - "$WINE_APP/Contents/Resources/wine/bin/wineserver" <<'PY'
import os,subprocess,sys
wanted=os.path.realpath(sys.argv[1])
for line in subprocess.check_output(['ps','-axo','comm='],text=True).splitlines():
    if os.path.basename(line.strip())=='wineserver' and os.path.realpath(line.strip())==wanted:
        sys.exit('Close the selected Wine prefix before replacing its Mac graphics driver.')
PY
python3 "$ROOT/scripts/patches/winemac-opengl-gdi.py" "$SRC"
# Tall windows with app-drawn title bars can be dragged onto a shorter screen (always on).
grep -q setting_frame_from_wine "$SRC/dlls/winemac.drv/cocoa_window.m" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/winemac-cross-screen-moves.patch"
# Windows owned by a zero-size owner (e.g. a hidden application window) draw on every display.
grep -q 'zero-size owner' "$SRC/dlls/winemac.drv/window.c" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/winemac-zero-size-owner.patch"
export PATH="$(sw_build_path "$BUILD/llvm-mingw/bin")"
mkdir -p "$ROOT/logs"
arch -x86_64 make -C "$OBJ" -j8 dlls/winemac.drv/winemac.so > "$ROOT/logs/winemac-gdi-build.log" 2>&1
python3 - "$OBJ/dlls/winemac.drv/winemac.so" "$WINE_APP/Contents/Resources/wine/lib/wine/x86_64-unix/winemac.so" <<'PY'
from pathlib import Path
import hashlib,shutil,subprocess,sys
src,dst=map(Path,sys.argv[1:])
backup=dst.with_name(dst.name+'.before-gdi')
if not backup.exists():shutil.copy2(dst,backup)
tmp=dst.with_name(dst.name+'.new');shutil.copy2(src,tmp)
subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(tmp)],check=True)
tmp.replace(dst)
dst.with_name(dst.name+'.gdi.sha256').write_text(hashlib.sha256(dst.read_bytes()).hexdigest()+'\n')
print('Installed Mac GDI presentation driver; run-solidworks.sh will enable it for this bundle.')
PY
