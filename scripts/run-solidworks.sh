#!/bin/zsh
# Start SolidWorks with the same command as the platform's desktop shortcut. SLDWORKS.exe refuses
# to run on its own ("must be launched from the 3DEXPERIENCE Platform").
# Mount the image first (01-storage.sh). TENANT and REGISTRY come from your own shortcut:
# C:\users\Public\Desktop\SOLIDWORKS Design.lnk
set -u
script_dir="${0:A:h}"
source "$script_dir/env.sh"
# Set this inside the script: macOS strips DYLD_* variables when starting /bin/zsh.
# Select the X11 driver separately and restart the prefix before using this option.
if [[ "${SW_GRAPHICS:-mac}" == x11 ]]; then
  export DYLD_FALLBACK_LIBRARY_PATH="/opt/X11/lib:/usr/lib"
fi
# Report x64 emulation on an ARM64 host on every Mac. The license loader's native-x64 path
# crashes under Wine ("cannot load JS0PCC.dll", then a null call), on Intel Macs as well;
# its x64-on-ARM64 path, which Windows on ARM also takes, starts normally.
export SW_REPORT_ARM64=1
TENANT="${SW_TENANT:?Set SW_TENANT in config.local.zsh from your own SOLIDWORKS shortcut}"
REGISTRY="${SW_REGISTRY:-https://eu1-makers-registry.3dexperience.3ds.com}"
W='C:\Program Files\Dassault Systemes\SOLIDWORKS 3DEXPERIENCE R2026x\win_b64\code\bin'
LOG_DIR="${SW_LOG_DIR:-$ROOT/logs}"
mkdir -p "$LOG_DIR"
# Truncate once here instead of at the CATSTART line below, so the launcher diagnostics written
# before the launch survive into the log a support request quotes.
: > "$LOG_DIR/solidworks-run.log"
# Installer state controls activation. Removing the setting takes effect after the
# installer also removes the app-local forwarder.
if [[ -d "$WINEPREFIX/.sw-intel-renderer" ]]; then
  renderer="$(python3 "$script_dir/tools/intel-renderer.py" check)" || exit 1
  [[ -n "$renderer" ]] || exit 1
  export WINEDLLPATH="$renderer${WINEDLLPATH:+:$WINEDLLPATH}"
  export WINEMETALGL_SW_FORMAT_FALLBACK=1 WINEMETALGL_CLIP_SIBLINGS=1
  export SW_TEST_SYNC_VIEWPORT_DRAWABLE=1 WINEMETALGL_EXTENSIONS_LENGTH=0
  export WINEMETALGL_VENDOR='ATI Technologies Inc.'
  print -r -- 'Using the installed Intel Metal renderer for SolidWorks.' >> "$LOG_DIR/solidworks-run.log"
fi
# Use a separate claim for each run, including launches that share a log directory.
TEARDOWN_DIR="$(mktemp -d "$LOG_DIR/.container-teardown.XXXXXX")" || exit 1
TEARDOWN_MARKER="$TEARDOWN_DIR/claimed"
cd "$WINEPREFIX/drive_c"
# The Launcher service can exit at boot with "Core function failed!", but starts fine afterwards,
# so start it on every launch. Do not gate this on the health probe: 127.0.0.1:20250 answers for
# *any* launcher on the machine, so a second Wine install makes the probe succeed while this
# prefix's launcher never starts - and a launcher that starts while the port is taken binds
# nothing, which leaves SolidWorks at "Connecting to 3DEXPERIENCE" for the whole session.
# `net start` is a no-op when the service is already up, so this costs nothing when all is well.
wine wineboot > /dev/null 2>&1
wine net start 3DEXPERIENCELauncher >> "$LOG_DIR/solidworks-run.log" 2>&1
if ! curl -s -m 3 -o /dev/null "http://127.0.0.1:20250/iframe?version=1.0&id=health"; then
  print -r -- "No 3DEXPERIENCE launcher answered on 127.0.0.1:20250." >> "$LOG_DIR/solidworks-run.log"
fi
# Only use our driver's options when this exact driver was installed by our builder.
# A later Wine update invalidates the marker and leaves normal rendering enabled.
GL_DRIVER="$WINE_APP/Contents/Resources/wine/lib/wine/x86_64-unix/winemac.so"
if [[ -f "$GL_DRIVER.gdi.sha256" ]]; then
  expected="$(<"$GL_DRIVER.gdi.sha256")"
  actual="$(shasum -a 256 "$GL_DRIVER" | cut -d ' ' -f 1)"
  if [[ "$actual" == "$expected" ]]; then
    # The 3D view is drawn natively and clipped to its visible region. SW_OPENGL_GDI=1 copies each
    # frame through GDI instead (slower; kept as a fallback).
    export SW_OPENGL_GDI="${SW_OPENGL_GDI:-0}"
    # This driver also matches window color spaces to Wine's sRGB images (no per-pixel conversion).
    export SW_MAC_SRGB="${SW_MAC_SRGB:-1}"
  fi
fi
# Only enable the scoped button guard for the exact matching library/prefix pair.
BUTTON_DLL="$WINE_APP/Contents/Resources/wine/lib/wine/x86_64-windows/comctl32_v6.dll"
if [[ -f "$BUTTON_DLL.capture.sha256" && -f "$WINEPREFIX/drive_c/windows/system32/comctl32_v6.dll" ]]; then
  expected="$(<"$BUTTON_DLL.capture.sha256")"
  actual="$(shasum -a 256 "$BUTTON_DLL" | cut -d ' ' -f 1)"
  prefix_actual="$(shasum -a 256 "$WINEPREFIX/drive_c/windows/system32/comctl32_v6.dll" | cut -d ' ' -f 1)"
  if [[ "$actual" == "$expected" && "$prefix_actual" == "$expected" ]]; then
    export SW_BUTTON_CAPTURE_GUARD="${SW_BUTTON_CAPTURE_GUARD:-1}"
  fi
fi
# gdi32 is a Wine builtin, so its patched PE must match between the bundle and the prefix. A Wine
# or prefix update replaces one half and leaves the pair mismatched, which paints the search
# results wrong again; fall back to the saved original instead of running a mixed pair.
GDI_DLL="$WINE_APP/Contents/Resources/wine/lib/wine/x86_64-windows/gdi32.dll"
GDI_PREFIX_DLL="$WINEPREFIX/drive_c/windows/system32/gdi32.dll"
if [[ -f "$GDI_DLL" && -f "$GDI_PREFIX_DLL" && -f "$GDI_DLL.stock" ]] &&
   ! cmp -s "$GDI_DLL" "$GDI_PREFIX_DLL"; then
  print -r -- "gdi32 mismatch between bundle and prefix; restoring the saved original" >> "$LOG_DIR/solidworks-run.log"
  cp "$GDI_DLL.stock" "$GDI_DLL"
  cp "$GDI_DLL.stock" "$GDI_PREFIX_DLL"
fi
# Automatic cross-process viewport resizing is disabled: it caused sketch crashes.
# Keep CAD's own geometry untouched. SwViewportFix is retained only for diagnosis.

# Processes belonging to this container: those that hold the prefix *and* run this Wine install.
# Both tests matter - the prefix directory is readable by anything that happens to have it open,
# so a backup, a shell with that working directory or a test harness would otherwise be signalled
# along with the container. If the install root cannot be identified this prints nothing, which
# leaves orphans behind rather than killing a process we do not own.
container_processes() {
  local root="${WINE_APP:-}/Contents/Resources/wine"
  [[ -d "$root" ]] || root="$(dirname "$(dirname "$(command -v wine 2>/dev/null)")")"
  [[ "$root" == /* ]] || return 0
  python3 "$script_dir/tools/container-processes.py" "$WINEPREFIX" "$root"
}

# SolidWorks leaves its platform behind when it exits: the launcher service, ViewServerV6 and
# the Visualize queue server keep running against a session that no longer exists, and the next
# start then finds the launcher "already running" while nothing answers it. Wait for them to
# leave on their own, then stop this prefix only - wineserver is prefix-scoped, so another Wine
# install on the same machine keeps its own processes.
stop_container() {
  # Stop the monitor before draining Wine. Its next helper would restart an
  # already-stopped prefix if it kept polling independently of the session.
  if [[ -n "${SW_SIGNIN_SESSION:-}" ]]; then
    touch "$SW_SIGNIN_SESSION/stop"
    for _ in {1..110}; do
      [[ -f "$SW_SIGNIN_SESSION/stopped" ]] && break
      sleep .1
    done
  fi
  wineserver -w > /dev/null 2>&1 &
  local waiter=$!
  for _ in {1.."${SW_SHUTDOWN_GRACE:-30}"}; do
    kill -0 "$waiter" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$waiter" 2>/dev/null; then
    print -r -- "SolidWorks exited; stopping leftover Wine processes for $WINEPREFIX" >> "$LOG_DIR/solidworks-run.log"
    wineserver -k > /dev/null 2>&1
    wait "$waiter" 2>/dev/null
  fi
  # A force-quit can take the server down before its session does, and `wineserver -k` only
  # reaches processes still registered with a live server. Anything left holding the prefix is
  # attached to nothing and will outlive every later start, so retire it by signal. Only processes
  # running this Wine install qualify: the prefix directory is also open in backups, shells and
  # test harnesses, and signalling one of those would be data loss.
  local stragglers
  stragglers=$(container_processes)
  if [[ -n "$stragglers" ]]; then
    print -r -- "sweeping $(wc -l <<< "$stragglers" | tr -d ' ') Wine processes still holding $WINEPREFIX" >> "$LOG_DIR/solidworks-run.log"
    kill ${(f)stragglers} 2>/dev/null
    sleep 3
    kill -9 ${(f)$(container_processes)} 2>/dev/null
  fi
}

# exe_running_in_prefix PATTERN NAME: a process whose mapped executable is NAME from this prefix.
exe_running_in_prefix() {
  local pid mapped drive="$WINEPREFIX/drive_c"
  drive=${drive:A}
  for pid in ${(f)"$(pgrep -if "$1" || true)"}; do
    for mapped in ${(f)"$(lsof -a -p "$pid" -d txt -Fn 2>/dev/null)"}; do
      if [[ "$mapped" == "n$drive/"* && "${mapped:l}" == */$2 ]]; then
        return 0
      fi
    done
  done
  return 1
}

cad_running_in_prefix() {
  exe_running_in_prefix 'sldworks[.]exe' sldworks.exe
}

# The launcher's "Update" button hands over to SWXDesktopUpdate.exe and exits. That downloads
# the hotfix through the 3DEXPERIENCE Launcher, which runs setup_noUAC.exe; the updater can exit
# before it finishes. setup_noUAC.exe stays until the install is done, so msiexec.exe is not
# watched: Wine's msiexec /V service never exits on its own and would hold teardown forever.
session_running_in_prefix() {
  cad_running_in_prefix ||
    exe_running_in_prefix 'swxdesktopupdate[.]exe' swxdesktopupdate.exe ||
    exe_running_in_prefix 'setup_nouac[.]exe' setup_nouac.exe
}

# Wait until the session has really ended. The updater hands its download to the Launcher service
# before setup_noUAC.exe appears, so one empty poll is not enough: require SW_SESSION_GRACE seconds
# with nothing running. CAD may run for days, but an update alone that outlives SW_UPDATE_TIMEOUT
# has hung (its page once stalled in a GPU crash loop); stop waiting so the launch lock is freed.
wait_for_session_end() {
  local quiet=0 started=$SECONDS
  while (( quiet < ${SW_SESSION_GRACE:-10} )); do
    if cad_running_in_prefix; then
      quiet=0 started=$SECONDS
    elif session_running_in_prefix; then
      quiet=0
      if (( SECONDS - started > ${SW_UPDATE_TIMEOUT:-7200} )); then
        print -r -- "The 3DEXPERIENCE update has not finished after ${SW_UPDATE_TIMEOUT:-7200}s; stopping Wine" >> "$LOG_DIR/solidworks-run.log"
        return
      fi
    else
      (( quiet += 2 ))
    fi
    sleep 2
  done
}

# A force-quit or a crash can leave CATSTART blocked in a call that never returns. Watch
# the CAD executable mapped from this prefix so another open SolidWorks session can't
# arm teardown during sign-in or delay it after this session has exited.
(
  # Only tear down a session that actually started. A launch parked on a login page can leave
  # CAD unborn for longer than any wait here, and retiring the launcher chain underneath it
  # would kill a sign-in the user is still working on.
  seen=0
  for _ in {1..900}; do
    if cad_running_in_prefix; then seen=1; break; fi
    sleep 1
  done
  if [[ "$seen" == 1 ]]; then
    wait_for_session_end
    if mkdir "$TEARDOWN_MARKER" 2>/dev/null; then
      stop_container
    fi
  fi
) &
watchdog=$!

wine "$W\\CATSTART.exe" -run "SWXDesktopLauncher.exe" \
    -object "--AppName=\"SWXCSWK_AP\" -tenant=$TENANT  -monoapp -3DRegistryURL=$REGISTRY" -nowindow \
    >> "$LOG_DIR/solidworks-run.log" 2>&1
launch_status=$?
# Claim the drain before interrupting the watchdog. If it already owns the claim, let it finish.
if mkdir "$TEARDOWN_MARKER" 2>/dev/null; then
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  # CATSTART can return successfully while the CAD process or an update still owns the
  # session. Keep both the launch lock and its sign-in monitor until they exit.
  wait_for_session_end
  stop_container
else
  wait "$watchdog" 2>/dev/null
fi
rmdir "$TEARDOWN_MARKER" "$TEARDOWN_DIR" 2>/dev/null
exit "$launch_status"
