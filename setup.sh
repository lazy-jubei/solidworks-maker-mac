#!/bin/zsh
# First-time Wine preparation. Does not install licensed SOLIDWORKS media.
set -eu
setup_root="${0:A:h}"
stages=(01-storage.sh 02-wine.sh 03-prefix.sh stop-prefix build-shell32.sh install-ntdll-shim.sh build-mac-gdi.sh build-button-capture.sh)
if (( $# > 1 )); then print -u2 'Usage: ./setup.sh [--dry-run|--help]'; exit 2; fi
case "${1:-}" in
  --help|-h)
    print 'Usage: ./setup.sh [--dry-run]'
    print 'Prepare Wine for a first SOLIDWORKS installation. Use scripts/install-guided.sh for the full installation.'
    exit 0 ;;
  --dry-run)
    for stage in "${stages[@]}"; do
      if [[ "$stage" == stop-prefix ]]; then print 'Stop the newly initialized Wine prefix'
      else print "scripts/$stage"; fi
    done
    exit 0 ;;
  '') ;;
  *) print -u2 'Usage: ./setup.sh [--dry-run|--help]'; exit 2 ;;
esac
source "$setup_root/scripts/env.sh"
# Refuse before creating files, mounting images or starting dependencies.
# This guard must also work before Python has been installed.
setup_server="$WINE_APP/Contents/Resources/wine/bin/wineserver"
setup_processes="$(ps -axo comm=)"
for setup_process in "${(@f)setup_processes}"; do
  setup_process="${setup_process#"${setup_process%%[![:space:]]*}"}"
  if [[ "${setup_process:t}" == wineserver && "${setup_process:A}" == "${setup_server:A}" ]]; then
    print -u2 'Save and close applications, then stop this Wine prefix before replacing its runtime.'
    exit 1
  fi
done
refuse_installed_prefix() {
  if [[ -f "$WINEPREFIX/drive_c/Program Files/Dassault Systemes/3DEXPERIENCE Launcher/3DEXPERIENCELauncher.exe" ]]; then
    print -u2 'This prefix already has the Launcher installed. Use the Mac app shortcut, or configure a separate image and prefix for a new installation.'
    exit 1
  fi
}
refuse_installed_prefix
trap 'rc=$?; if [[ -n "${build_pid:-}" ]]; then kill "$build_pid" 2>/dev/null || true; fi; exit $rc' EXIT
"$setup_root/scripts/tools/check-setup-requirements.sh"
if [[ "${SW_CONFIG_FILE:h:A}" == "$setup_root" && "${SW_CONFIG_FILE:t}" == config.local.zsh && ! -f "$SW_CONFIG_FILE" ]]; then
  cp "$setup_root/config.example.zsh" "$SW_CONFIG_FILE"
fi
# A clean prepared prefix is kept on the image after a full preparation, so later installs
# copy it (a minute or two) instead of running winetricks again. It is only used while
# the setup scripts, patches and pinned versions that made it are unchanged.
template="${SW_PREFIX_TEMPLATE:-$VOL/prefix-template-$WINE_VERSION}"
template_stamp() {
  local files=("$setup_root/setup.sh")
  local stage
  for stage in "${stages[@]}"; do
    if [[ "$stage" != stop-prefix ]]; then files+=("$setup_root/scripts/$stage"); fi
  done
  files+=("$setup_root"/scripts/patches/**/*(.N))
  { print -r -- "$WINE_FLAVOR $WINE_VERSION $WINETRICKS_VERSION"; cat -- "${files[@]}"; } | shasum -a 256 | cut -d' ' -f1
}
# Keep locally supplied fonts out of the reusable template.
install_optional_fonts() {
  if [[ -z "${SW_WINDOWS_FONTS_DIR:-}" ]]; then
    print 'For Segoe UI, set SW_WINDOWS_FONTS_DIR to a local font directory.'
    return 0
  fi
  local font_status=0
  "$setup_root/scripts/install-windows-fonts.sh" "$SW_WINDOWS_FONTS_DIR" || font_status=$?
  wineserver -k || true
  wineserver -w
  return "$font_status"
}
# On a first install, compile the patched Wine parts while winetricks fills the prefix:
# compiling only reads the source and build folders. Installing them waits for Wine to stop.
build_pid=''
wait_for_build() {
  if [[ -n "$build_pid" ]]; then
    if ! wait "$build_pid"; then
      build_pid=''
      print -u2 "Compiling Wine failed; see $ROOT/logs/wine-build.log"
      tail -20 "$ROOT/logs/wine-build.log" >&2
      exit 1
    fi
    build_pid=''
  fi
}
for stage in "${stages[@]}"; do
  if [[ "$stage" == stop-prefix ]]; then
    print 'Stopping the newly initialized Wine prefix…'
    wineserver -k
    wineserver -w
    continue
  fi
  if [[ "$stage" == 03-prefix.sh ]]; then
    stamp="$(template_stamp)"
    if [[ ! -e "$WINEPREFIX" && -f "$template/.sw-template-stamp" \
          && "$(<"$template/.sw-template-stamp")" == "$stamp" ]]; then
      print 'Copying the prepared Wine prefix (made by an earlier setup)…'
      ditto "$template" "$WINEPREFIX"
      rm -f "$WINEPREFIX/.sw-template-stamp"
      install_optional_fonts
      print 'Wine preparation complete.'
      exit 0
    fi
    if [[ ! -f "$VOL/build/obj-wine-$WINE_VERSION/dlls/shell32/x86_64-windows/shell32.dll" ]]; then
      print "Compiling Wine's patched libraries alongside the prefix (log: logs/wine-build.log)…"
      mkdir -p "$ROOT/logs"
      SW_BUILD_ONLY=1 "$setup_root/scripts/build-shell32.sh" < /dev/null > "$ROOT/logs/wine-build.log" 2>&1 &
      build_pid=$!
    fi
  fi
  if [[ "$stage" == build-shell32.sh ]]; then wait_for_build; fi
  print "Running $stage…"
  "$setup_root/scripts/$stage"
  # An existing image may have been unmounted during the first check.
  if [[ "$stage" == 01-storage.sh ]]; then refuse_installed_prefix; fi
done
print 'Saving the prepared Wine prefix for later installs…'
rm -rf -- "$template.partial"
ditto "$WINEPREFIX" "$template.partial"
print -r -- "$(template_stamp)" > "$template.partial/.sw-template-stamp"
rm -rf -- "$template"
mv -- "$template.partial" "$template"
install_optional_fonts
print 'Wine preparation complete.'
