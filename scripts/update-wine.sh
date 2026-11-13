#!/bin/zsh
# Apply this release's supported Wine patches and browser graphics in place.
# Never invoke setup.sh, prefix initialization or the guided reinstall here.
set -eu
unset SW_BUILD_ONLY
(( $# == 0 )) || { print -u2 'Usage: scripts/update-wine.sh'; exit 2; }
source "${0:A:h}/env.sh"
lock="$ROOT/.sw-update-lock"
mkdir "$lock" 2>/dev/null || { print -u2 'Another update is running (or left .sw-update-lock after interruption).'; exit 1; }
trap 'rmdir "$lock"' EXIT
[[ -d "$IMAGE" ]] || { print -u2 "Existing Wine image not found: $IMAGE"; exit 1; }
"$ROOT/scripts/01-storage.sh"
[[ -x "$WINE_APP/Contents/Resources/wine/bin/wine" && -f "$WINEPREFIX/system.reg" ]] || {
  print -u2 'The existing runtime/prefix does not match this release. Automatic Wine version migration is not supported.'
  exit 1
}
server="$WINE_APP/Contents/Resources/wine/bin/wineserver"
python3 "$ROOT/scripts/tools/require-stopped.py" "$server"
mkdir -p "$ROOT/logs"
# Build prerequisites first. Existing runtime and prefix stay in place.
"$ROOT/scripts/tools/check-setup-requirements.sh"
for stage in 02-wine.sh build-shell32.sh install-ntdll-shim.sh build-mac-gdi.sh build-button-capture.sh; do
  python3 "$ROOT/scripts/tools/require-stopped.py" "$server"
  "$ROOT/scripts/$stage"
done
# Registry commands start background Wine services. Stop them before DLL deployment,
# and on failure, rather than leaving half-finished update processes running.
trap 'WINEPREFIX="$WINEPREFIX" "$server" -k 2>/dev/null || true; WINEPREFIX="$WINEPREFIX" "$server" -w 2>/dev/null || true; rmdir "$lock"' EXIT
"$ROOT/scripts/install-windows-fonts.sh"
"$ROOT/scripts/build-signin-tools.sh"
"$server" -k
"$server" -w
"$ROOT/scripts/install-dxmt.sh"
"$ROOT/scripts/06-settings.sh"
"$server" -k
"$server" -w
"$ROOT/scripts/09-mac-launcher.sh"
print 'Wine patches and browser graphics updated. Open SolidWorks (Wine) from Applications.'
