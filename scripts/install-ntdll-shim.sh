#!/bin/zsh
# Build swshim.dll and add forwarded exports to the stock Staging ntdll.dll.
# Run with no Wine processes using this prefix (build-shell32.sh provides llvm-mingw).
set -eu
source "${0:A:h}/env.sh"
python3 "${0:A:h}/tools/require-stopped.py" "$WINE_APP/Contents/Resources/wine/bin/wineserver"
PATCHES="${0:A:h}/patches"
LLVM="$VOL/build/llvm-mingw"
LIBW="$WINE_APP/Contents/Resources/wine/lib/wine/x86_64-windows"
TMPOUT="$VOL/tmp/swshim.dll"

"$LLVM/bin/x86_64-w64-mingw32-clang" -O2 -shared -nostdlib -Wl,-e,DllMainCRTStartup \
    "$PATCHES/swshim.c" -lntdll -o "$TMPOUT"
cp "$TMPOUT" "$WINEPREFIX/drive_c/windows/system32/swshim.dll"

[[ -f "$LIBW/ntdll.dll.stock" ]] || cp "$LIBW/ntdll.dll" "$LIBW/ntdll.dll.stock"
python3 -I "$PATCHES/pe-add-forward-exports.py" "$LIBW/ntdll.dll.stock" "$VOL/tmp/ntdll.new" \
    RtlIsNameInExpression=swshim.RtlIsNameInExpression
# Rename rather than overwrite, so a running process keeps its mapped copy intact.
cp "$VOL/tmp/ntdll.new" "$LIBW/ntdll.dll.new"
mv "$LIBW/ntdll.dll.new" "$LIBW/ntdll.dll"
cp "$LIBW/ntdll.dll" "$VOL/tmp/ntdll.prefix"
mv "$VOL/tmp/ntdll.prefix" "$WINEPREFIX/drive_c/windows/system32/ntdll.dll"
echo SHIM-OK
