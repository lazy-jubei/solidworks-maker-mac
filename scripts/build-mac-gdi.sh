#!/bin/zsh
# Build and install SOLIDWORKS' Mac graphics pieces into the selected Wine bundle:
#  - winemac.so: GL views clipped to their visible region (the FeatureManager stays visible),
#    optional GDI presentation (SW_OPENGL_GDI=1), sRGB windows, multi-monitor fixes;
#  - opengl32: simple GL calls batched into one PE/unix transition (WINE_GL_BATCH=0 disables).
# Stop the selected prefix before installing. No vendor DLLs change.
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
# OpenGL redraw callbacks can call OnMainThread from the Cocoa main thread: run them inline.
grep -q 'Cocoa callbacks can reach this helper' "$SRC/dlls/winemac.drv/cocoa_event.m" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/winemac-main-thread-reentry.patch"
# GDI-presented GL frames reach the screen at once (not every 50 ms); optional sRGB windows.
grep -q macdrv_flush_present_surface "$SRC/dlls/winemac.drv/surface.c" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/winemac-gdi-present-flush.patch"
# Native GL views clipped to their visible region (default; faster than GDI presentation).
grep -q exclude_higher_siblings "$SRC/dlls/winemac.drv/window.c" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/winemac-clip-gl-views.patch"
# Batch the z-order lookup when several siblings can cover the viewport.
grep -q 'sending a server request for every GW_HWNDPREV' "$SRC/dlls/winemac.drv/window.c" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/winemac-batch-clip-siblings.patch"
# One PE/unix transition per batch of simple GL calls instead of one per call.
grep -q wine_batch_execute "$SRC/dlls/opengl32/unix_thunks.c" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/opengl32-batch-calls.patch"
export PATH="$(sw_build_path "$BUILD/llvm-mingw/bin")"
mkdir -p "$ROOT/logs"
arch -x86_64 make -C "$OBJ" -j8 dlls/winemac.drv/winemac.so dlls/opengl32/opengl32.so \
  dlls/opengl32/x86_64-windows/opengl32.dll > "$ROOT/logs/winemac-gdi-build.log" 2>&1
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
# opengl32's PE and unix halves share a call table, so both are replaced together (originals kept).
python3 - "$OBJ/dlls/opengl32" "$WINE_APP/Contents/Resources/wine/lib/wine" "$WINEPREFIX/drive_c/windows/system32" <<'PY'
from pathlib import Path
import shutil,subprocess,sys
obj,lib,system32=map(Path,sys.argv[1:])
pairs=[(obj/'x86_64-windows/opengl32.dll',lib/'x86_64-windows/opengl32.dll'),
       (obj/'opengl32.so',lib/'x86_64-unix/opengl32.so'),
       (obj/'x86_64-windows/opengl32.dll',system32/'opengl32.dll')]
for src,dst in pairs:
    backup=dst.with_name(dst.name+'.stock')
    if dst.exists() and not backup.exists():shutil.copy2(dst,backup)
    tmp=dst.with_name(dst.name+'.new');shutil.copy2(src,tmp)
    if dst.suffix=='.so':subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(tmp)],check=True)
    tmp.replace(dst)
print('Installed batched opengl32 (WINE_GL_BATCH=0 turns batching off).')
PY
