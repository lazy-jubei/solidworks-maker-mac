#!/bin/zsh
# Build Wine's 64-bit shell32.dll with zip folder support and install it into the Wine
# bundle (the original is kept as shell32.dll.stock). Everything stays on the image.
# Needs Xcode Command Line Tools and Homebrew bison; about 15 minutes the first time.
set -eu
source "${0:A:h}/env.sh"
python3 "${0:A:h}/tools/require-stopped.py" "$WINE_APP/Contents/Resources/wine/bin/wineserver"
PATCHES="${0:A:h}/patches"
BUILD="${SW_BUILD:-$VOL/build}"
SRC="$BUILD/src-wine-$WINE_VERSION"
OBJ="$BUILD/obj-wine-$WINE_VERSION"
TAR="$CACHE/wine-$WINE_VERSION.tar.xz"
TAR_SHA="c66e2090343dcd727f7f7fd2f87ee0bfb0b118790c1d745ab7b8a4c3a4197f2f"
mkdir -p "$BUILD" "$ROOT/logs"

[[ -f "$TAR" ]] || curl -fL -o "$TAR" "https://dl.winehq.org/wine/source/11.x/wine-$WINE_VERSION.tar.xz"
echo "$TAR_SHA  $TAR" | shasum -a 256 -c -

LLVM="$BUILD/llvm-mingw"
if [[ ! -x "$LLVM/bin/x86_64-w64-mingw32-clang" ]]; then
  LLVM_TAG="20261020"
  asset="llvm-mingw-$LLVM_TAG-ucrt-macos-universal.tar.xz"
  [[ -f "$CACHE/$asset" ]] || curl -fL -o "$CACHE/$asset" "https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_TAG/$asset"
  tar -xJf "$CACHE/$asset" -C "$BUILD"
  mv "$BUILD/llvm-mingw-$LLVM_TAG-ucrt-macos-universal" "$LLVM"
  echo "llvm-mingw $LLVM_TAG"
fi

if [[ ! -d "$SRC" ]]; then
  tar -xJf "$TAR" -C "$BUILD"
  mv "$BUILD/wine-$WINE_VERSION" "$SRC"
  python3 -I "$PATCHES/apply-shell32-zipfolder.py" "$SRC"
  python3 -I "$PATCHES/shell32-fileop-copy.py" "$SRC"
  python3 -I "$PATCHES/wininet-websocket-stubs.py" "$SRC"
  python3 -I "$PATCHES/wininet-cookie2.py" "$SRC"
  python3 -I "$PATCHES/services-elevated.py" "$SRC"
  python3 -I "$PATCHES/msi-addlocal-parents.py" "$SRC"
  python3 -I "$PATCHES/wow64-commit-limit.py" "$SRC"
  python3 -I "$PATCHES/kernelbase-report-arm64.py" "$SRC"
  python3 -I "$PATCHES/kernelbase-standard-integrity.py" "$SRC"
  python3 -I "$PATCHES/comctl32-header-layout.py" "$SRC"
else
  cp "$PATCHES/shell32-zipfolder.c" "$SRC/dlls/shell32/zipfolder.c"
  python3 -I "$PATCHES/wininet-cookie2.py" "$SRC"
  python3 -I "$PATCHES/kernelbase-standard-integrity.py" "$SRC"
  grep -q SW_REPORT_ARM64 "$SRC/dlls/kernelbase/process.c" || python3 -I "$PATCHES/kernelbase-report-arm64.py" "$SRC"
  grep -q 'if (!lpLayout) return FALSE' "$SRC/dlls/comctl32/header.c" || python3 -I "$PATCHES/comctl32-header-layout.py" "$SRC"
fi

export PATH="$LLVM/bin:/opt/homebrew/opt/bison/bin:/usr/bin:/bin:/opt/homebrew/bin"
export TMPDIR="$VOL/tmp"
mkdir -p "$OBJ"
if [[ ! -f "$OBJ/Makefile" ]]; then
  ( cd "$OBJ" && arch -x86_64 env CC="/usr/bin/clang -arch x86_64" "$SRC/configure" \
      --build=x86_64-apple-darwin --enable-archs=i386,x86_64 --with-mingw --disable-tests \
      --without-x --without-freetype --without-gnutls --without-gstreamer --without-sdl \
      --without-vulkan --without-opencl --without-pcap --without-pcsclite --without-cups \
      --without-inotify --without-krb5 --without-gssapi --without-netapi --without-usb \
      --without-v4l2 --without-sane --without-pulse --without-oss --without-alsa \
      --without-capi --without-dbus --without-gphoto --without-udev --without-wayland \
      --without-ffmpeg --without-gettext --without-gettextpo )
fi
( cd "$OBJ" && arch -x86_64 make -j"$(/usr/sbin/sysctl -n hw.ncpu)" dlls/shell32/x86_64-windows/shell32.dll dlls/wininet/x86_64-windows/wininet.dll programs/services/x86_64-windows/services.exe dlls/msi/x86_64-windows/msi.dll dlls/msi/i386-windows/msi.dll dlls/wow64/x86_64-windows/wow64.dll dlls/kernelbase/x86_64-windows/kernelbase.dll dlls/comctl32/x86_64-windows/comctl32.dll dlls/comctl32_v6/x86_64-windows/comctl32_v6.dll )

DST="$WINE_APP/Contents/Resources/wine/lib/wine/x86_64-windows/shell32.dll"
[[ -f "$DST.stock" ]] || cp "$DST" "$DST.stock"
cp "$OBJ/dlls/shell32/x86_64-windows/shell32.dll" "$DST"
cp "$DST" "$WINEPREFIX/drive_c/windows/system32/shell32.dll"
shasum -a 256 "$DST"
WIN="${DST:h}/wininet.dll"
[[ -f "$WIN.stock" ]] || cp "$WIN" "$WIN.stock"
cp "$OBJ/dlls/wininet/x86_64-windows/wininet.dll" "$WIN"
cp "$WIN" "$WINEPREFIX/drive_c/windows/system32/wininet.dll"
SVC="${DST:h}/services.exe"
[[ -f "$SVC.stock" ]] || cp "$SVC" "$SVC.stock"
cp "$OBJ/programs/services/x86_64-windows/services.exe" "$SVC"
cp "$SVC" "$WINEPREFIX/drive_c/windows/system32/services.exe"
MSI="${DST:h}/msi.dll"
[[ -f "$MSI.stock" ]] || cp "$MSI" "$MSI.stock"
cp "$OBJ/dlls/msi/x86_64-windows/msi.dll" "$MSI"
cp "$MSI" "$WINEPREFIX/drive_c/windows/system32/msi.dll"
MSI32="${DST:h:h}/i386-windows/msi.dll"
[[ -f "$MSI32.stock" ]] || cp "$MSI32" "$MSI32.stock"
cp "$OBJ/dlls/msi/i386-windows/msi.dll" "$MSI32"
cp "$MSI32" "$WINEPREFIX/drive_c/windows/syswow64/msi.dll"
W64="${DST:h}/wow64.dll"
[[ -f "$W64.stock" ]] || cp "$W64" "$W64.stock"
cp "$OBJ/dlls/wow64/x86_64-windows/wow64.dll" "$W64"
cp "$W64" "$WINEPREFIX/drive_c/windows/system32/wow64.dll"
for mod in kernelbase comctl32 comctl32_v6; do
  LIB="$WINE_APP/Contents/Resources/wine/lib/wine/x86_64-windows/$mod.dll"
  [[ -f "$LIB.stock" ]] || cp "$LIB" "$LIB.stock"
  cp "$OBJ/dlls/$mod/x86_64-windows/$mod.dll" "$LIB"
  cp "$LIB" "$WINEPREFIX/drive_c/windows/system32/$mod.dll"
done
echo BUILD-OK
