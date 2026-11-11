#!/bin/zsh
# Download and unpack the pinned Wine build and winetricks; verify they run.
set -eu
source "${0:A:h}/env.sh"
python3 "${0:A:h}/tools/require-stopped.py" "$WINE_APP/Contents/Resources/wine/bin/wineserver"
TAR="$CACHE/${WINE_URL:t}"
[[ -f "$TAR" ]] || { curl --proto '=https' -fL -o "$TAR.part" "$WINE_URL"; mv "$TAR.part" "$TAR"; }
shasum -a 256 "$TAR" | tee "$CACHE/${WINE_URL:t}.sha256"
if [[ ! -d "$WINE_APP" ]]; then
  mkdir -p "${WINE_APP:h}"
  tar -xJf "$TAR" -C "${WINE_APP:h}"
fi
ls "${WINE_APP:h}"
xattr -dr com.apple.quarantine "$WINE_APP" 2>/dev/null || true
# Rosetta 32<->64-bit mode-switch fix and wineserver crash fix, from the altium-wine kit
# (LGPL 2.1+, github.com/lazy-jubei/altium-wine). Originals are kept as *.stock.
RES="$WINE_APP/Contents/Resources/wine"
CPU="$RES/lib/wine/x86_64-windows/wow64cpu.dll"
if [[ "$SW_HOST_ARM64" == 1 && ! -f "$CPU.stock" ]]; then
  cp "$CPU" "$CPU.stock"
  python3 -I "${0:A:h}/patches/wow64cpu-rosetta-trampoline.py" "$CPU.stock" "$CPU"
fi
if [[ ! -f "$RES/bin/wineserver.stock" ]]; then
  cp "$RES/bin/wineserver" "$RES/bin/wineserver.stock"
  python3 -I "${0:A:h}/patches/wineserver-wakeup-epipe.py" "$RES/bin/wineserver.stock" "$RES/bin/wineserver"
  codesign -s - -f "$RES/bin/wineserver"
fi

# Keep the Staging protocol and stop enumeration of unlinked windows on teardown.
server_candidate="$(mktemp "$RES/bin/wineserver.XXXXXXXX")"
trap '/bin/rm -- "$server_candidate"' EXIT
python3 -I "${0:A:h}/patches/wineserver-window-list.py" "$RES/bin/wineserver" "$server_candidate"
if ! cmp -s "$RES/bin/wineserver" "$server_candidate"; then
  codesign -s - -f "$server_candidate"
  codesign --verify --strict "$server_candidate"
  mv -f "$server_candidate" "$RES/bin/wineserver"
else
  /bin/rm -- "$server_candidate"
fi
trap - EXIT
[[ -x "$VOL/bin/winetricks" ]] || { curl --proto '=https' -fL -o "$VOL/bin/winetricks" "$WINETRICKS_URL"; chmod +x "$VOL/bin/winetricks"; }
wine --version
winetricks --version
