#!/bin/zsh
# Build and install SOLIDWORKS' Mac graphics pieces into the selected Wine bundle:
#  - winemac.so: GL views clipped to their visible region (the FeatureManager stays visible),
#    optional GDI presentation (SW_OPENGL_GDI=1), sRGB windows, multi-monitor fixes, and a live
#    resize that shows the window colour where the app has not painted yet instead of a stretched
#    copy of the previous frame;
#  - opengl32: simple GL calls batched into one PE/unix transition (WINE_GL_BATCH=0 disables).
#  - gdi32: render the SolidWorks search results without a trailing NUL glyph.
#  - win32u: present the SolidWorks status bar after paint, close embedded browser windows,
#    and preserve mouse capture during live resize.
# Stop the selected prefix before installing. Only Wine's own DLLs change (gdi32 is a Wine
# builtin, so its patched PE goes in the bundle and in the prefix); vendor DLLs are untouched.
# Each replaced file keeps its original next to it as <name>.stock.
set -eu
source "${0:A:h}/env.sh"
BUILD="${SW_BUILD:-$VOL/build}"
SRC="$BUILD/src-wine-$WINE_VERSION"
OBJ="$BUILD/obj-wine-$WINE_VERSION"
if [[ ! -f "$OBJ/Makefile" ]] ||
   ! grep -Fxq '#define SONAME_LIBFREETYPE "@loader_path/../../libfreetype.6.dylib"' "$OBJ/include/config.h"; then
  print -u2 'Configure the Wine source with build-shell32.sh before replacing win32u.'
  exit 1
fi
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
# Read both clipping siblings from one wineserver reply and reuse the known top-level window.
grep -q 'client_surface_get_clip(.*HWND toplevel' "$SRC/dlls/winemac.drv/window.c" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/winemac-resize-clip-queries.patch"
# Respect the FeatureManager's shaped splitter edge when clipping the viewport.
grep -q 'The SOLIDWORKS sidebar has a shaped edge' "$SRC/dlls/winemac.drv/window.c" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/winemac-shaped-featuremanager-clip.patch"
# Wait for tooltip pixels before ordering the popup onto the screen.
grep -q performPendingTooltipOrder "$SRC/dlls/winemac.drv/cocoa_window.m" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/winemac-tooltip-first-paint.patch"
# SOLIDWORKS uses a custom window class for its status-bar warning balloon.
grep -q swBalloonTip "$SRC/dlls/winemac.drv/window.c" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/winemac-solidworks-balloon-first-paint.patch"
# Snapshot Options pixels and repaint scrolls from the controls.
grep -q macdrv_ScrollDC "$SRC/dlls/winemac.drv/gdi.c" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/winemac-solidworks-ui-repaint.patch"
# Keep SolidWorks status tooltips within the display work area before showing them.
grep -q 'paintSettleMs:.*constrainTip:' "$SRC/dlls/winemac.drv/cocoa_window.m" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/winemac-solidworks-tooltip-screen.patch"
# Show the strip a live resize exposes in the window colour instead of a stretched old frame
# (SW_MAC_RESIZE_GRAVITY=0 restores the stretching).
grep -q macdrv_resize_band_background "$SRC/dlls/winemac.drv/cocoa_window.m" \
  || python3 "$ROOT/scripts/patches/winemac-resize-layer-gravity.py" "$SRC"
# The search result passes a terminating NUL in the displayed character count.
grep -q 'includes the terminator when painting' "$SRC/dlls/gdi32/text.c" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/gdi32-solidworks-search-label.patch"
# One PE/unix transition per batch of simple GL calls instead of one per call.
grep -q wine_batch_execute "$SRC/dlls/opengl32/unix_thunks.c" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/opengl32-batch-calls.patch"
grep -q begin_solidworks_status_paint "$SRC/dlls/win32u/dce.c" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/win32u-solidworks-status-paint.patch"
grep -q destroy_window_with_notification "$SRC/dlls/win32u/window.c" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/win32u-solidworks-browser-destroy.patch"
grep -q is_solidworks_browser_on_another_thread "$SRC/dlls/win32u/window.c" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/win32u-solidworks-browser-layout.patch"
grep -q 'Only that loop should release its capture' "$SRC/dlls/win32u/menu.c" \
  || patch -d "$SRC" -p1 -s -N < "$ROOT/scripts/patches/win32u-preserve-sizing-capture.patch"
# Apply or remove the optional embedded login changes on the existing build tree.
embedded_patch="$ROOT/scripts/patches/winemac-embedded-signin.patch"
embedded=${SW_EMBEDDED_SIGNIN:-0}
if [[ "$embedded" == 1 ]]; then
  grep -Fq SW_MAC_EMBEDDED_SIGNIN "$SRC/dlls/win32u/dce.c" ||
    git -C "$SRC" apply "$embedded_patch"
elif grep -Fq SW_MAC_EMBEDDED_SIGNIN "$SRC/dlls/win32u/dce.c"; then
  git -C "$SRC" apply -R "$embedded_patch"
fi
export PATH="$(sw_build_path "$BUILD/llvm-mingw/bin")"
mkdir -p "$ROOT/logs"
arch -x86_64 make -C "$OBJ" -j8 dlls/winemac.drv/winemac.so dlls/opengl32/opengl32.so \
  dlls/opengl32/x86_64-windows/opengl32.dll dlls/gdi32/x86_64-windows/gdi32.dll \
  dlls/win32u/win32u.so > "$ROOT/logs/winemac-gdi-build.log" 2>&1
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
# Keep the original modules alongside their signed replacements.
python3 - "$OBJ/dlls" "$WINE_APP/Contents/Resources/wine/lib/wine" "$WINEPREFIX/drive_c/windows/system32" \
  "$embedded" <<'PY'
from pathlib import Path
import hashlib,shutil,subprocess,sys
obj,lib,system32=map(Path,sys.argv[1:4])
pairs=[(obj/'opengl32/x86_64-windows/opengl32.dll',lib/'x86_64-windows/opengl32.dll'),
       (obj/'opengl32/opengl32.so',lib/'x86_64-unix/opengl32.so'),
       (obj/'opengl32/x86_64-windows/opengl32.dll',system32/'opengl32.dll'),
       (obj/'gdi32/x86_64-windows/gdi32.dll',lib/'x86_64-windows/gdi32.dll'),
       (obj/'gdi32/x86_64-windows/gdi32.dll',system32/'gdi32.dll'),
       (obj/'win32u/win32u.so',lib/'x86_64-unix/win32u.so')]
for src,dst in pairs:
    backup=dst.with_name(dst.name+'.stock')
    if dst.exists() and not backup.exists():shutil.copy2(dst,backup)
    tmp=dst.with_name(dst.name+'.new');shutil.copy2(src,tmp)
    if dst.suffix=='.so':subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(tmp)],check=True)
    tmp.replace(dst)
unix = lib / 'x86_64-unix'
marker = unix / 'embedded-signin.sha256'
if sys.argv[4] == '1':
    temporary = marker.with_suffix('.new')
    temporary.write_text(''.join(
        f'{hashlib.sha256((unix / module).read_bytes()).hexdigest()}  {module}\n'
        for module in ('win32u.so', 'winemac.so')))
    temporary.replace(marker)
else:
    marker.unlink(missing_ok=True)
print('Installed batched OpenGL, SolidWorks search text, and status bar paint fixes.')
PY
