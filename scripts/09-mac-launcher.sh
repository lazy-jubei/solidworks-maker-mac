#!/bin/zsh
# Build a local Finder shortcut; keep the checkout and its local config in place.
set -eu
case "${1:-}" in ''|--test) ;; *) print -u2 'usage: 09-mac-launcher.sh [--test]'; exit 2;; esac
python3 - "${1:-}" "${0:A:h}" <<'PY'
from pathlib import Path
import plistlib
import shlex
import sys
fresh = sys.argv[1] == '--test'
scripts = Path(sys.argv[2]).resolve()
project = scripts.parent
name = 'SolidWorks Fresh (Wine)' if fresh else 'SolidWorks (Wine)'
app = Path.home() / 'Applications' / (name + '.app')
mac = app / 'Contents/MacOS'
mac.mkdir(parents=True, exist_ok=True)
runtime = app / 'Contents/Resources/runtime'
for relative in ('env.sh', 'run-solidworks.sh', '10-fresh-signin.sh', 'tools/signin-monitor.py','tools/launch-once.py'):
    dst = runtime / 'scripts' / relative
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes((scripts / relative).read_bytes())
    dst.chmod(0o755)
code = '''#!/bin/zsh
set -eu
umask 077
mkdir -p "$HOME/Library/Logs/SolidWorksWine"
exec >> "$HOME/Library/Logs/SolidWorksWine/@LOG@-launcher.log" 2>&1
print -r -- "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ') Starting SolidWorks @LOG@ launcher"
unset SW_VOL SW_PREFIX SW_IMAGE SW_BUILD SW_GRAPHICS SW_VIEWPORT_FIX SW_OPENGL_GDI SW_BUTTON_CAPTURE_GUARD SW_PROJECT_ROOT SW_LOG_DIR
unset WINEDLLOVERRIDES SW_REPORT_STANDARD_INTEGRITY WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS WINE_D3D_CONFIG
export SW_PROJECT_ROOT="${0:A:h:h}/Resources/runtime"
export SW_CONFIG_FILE=@CONFIG@
export SW_IMAGE=@MAIN_IMAGE@
_sw_launcher_image_default=@IMAGE@
source "$SW_PROJECT_ROOT/scripts/env.sh"
@FRESH@
if [[ ! -d "$VOL" ]]; then
  hdiutil attach -nobrowse -mountpoint "$VOL" "$IMAGE"
fi
[[ -x "$WINE_APP/Contents/Resources/wine/bin/wine" ]] || { print -u2 'The selected image is missing its Wine runtime; complete setup first.'; exit 1; }
export SW_LOG_DIR="$HOME/Library/Logs/SolidWorksWine/@LOG@-runtime"
exec "$SW_PROJECT_ROOT/scripts/10-fresh-signin.sh"
'''
code = code.replace('@LOG@', 'fresh' if fresh else 'main')
code = code.replace('@CONFIG@', shlex.quote(str(project/'config.local.zsh')))
code = code.replace('@MAIN_IMAGE@', shlex.quote(str(project/'swwine.sparsebundle')))
code = code.replace('@IMAGE@', shlex.quote(str(project/('swwine-test.sparsebundle' if fresh else 'swwine.sparsebundle'))))
fresh_config = r'''# Keep account/region settings, but isolate all main storage/prefix selectors.
_sw_launcher_main_prefix="$WINEPREFIX"
_sw_launcher_main_image="$IMAGE"
export SW_VOL="${SW_TEST_VOL:-/Volumes/SWWineT}"
export SW_PREFIX="${SW_TEST_PREFIX:-$SW_VOL/prefix-$WINE_VERSION}"
export SW_IMAGE="${SW_TEST_IMAGE:-$_sw_launcher_image_default}"
# Subsequent env.sh calls must not reload the main selectors over these values.
export SW_CONFIG_FILE=/dev/null
source "$SW_PROJECT_ROOT/scripts/env.sh"
if [[ "${WINEPREFIX:A}" == "${_sw_launcher_main_prefix:A}" || "$WINEPREFIX" -ef "$_sw_launcher_main_prefix" ]]; then
  print -u2 'The fresh shortcut must use a different prefix from the main installation.'
  exit 1
fi
if [[ "${IMAGE:A}" == "${_sw_launcher_main_image:A}" || "$IMAGE" -ef "$_sw_launcher_main_image" ]]; then
  print -u2 'The fresh shortcut must use a different disk image from the main installation.'
  exit 1
fi
'''
code = code.replace('@FRESH@', fresh_config if fresh else '')
launch = mac/'launch'
launch.write_text(code)
launch.chmod(0o755)
with (app/'Contents/Info.plist').open('wb') as out:
    plistlib.dump({'CFBundleExecutable':'launch',
                  'CFBundleIdentifier':'local.solidworks-wine.launcher'+('.fresh' if fresh else ''),
                  'CFBundleName':name, 'CFBundleDisplayName':name,
                  'CFBundlePackageType':'APPL', 'CFBundleVersion':'2',
                  'CFBundleShortVersionString':'0.1.1', 'LSMinimumSystemVersion':'10.15',
                  'NSNetworkVolumesUsageDescription':'SOLIDWORKS needs access to its Windows disk image.',
                  'NSRemovableVolumesUsageDescription':'SOLIDWORKS runs from its mounted Windows disk image.'},out)
print(app)
PY
