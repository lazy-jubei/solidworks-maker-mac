#!/bin/zsh
# Register locally supplied Windows fonts in an existing Wine prefix.
set -eu
source "${0:A:h}/env.sh"

font_dir="${1:-${SW_WINDOWS_FONTS_DIR:-}}"
usage() {
  print 'Usage: scripts/install-windows-fonts.sh <directory containing segoeui.ttf>'
}
if [[ "${1:-}" == --help ]] && (( $# == 1 )); then
  usage
  exit 0
fi
if (( $# > 1 )) || [[ -z "$font_dir" ]]; then
  usage >&2
  exit 2
fi
typeset -A source_files
for source_file in "$font_dir"/*.[tT][tT][fF](N); do
  [[ -f "$source_file" ]] || continue
  filename="${source_file:t}"
  source_files[${filename:l}]="$source_file"
done
if [[ ! -r "${source_files[segoeui.ttf]:-}" ]]; then
  print -u2 -- "Missing readable Segoe UI font: $font_dir/segoeui.ttf"
  exit 1
fi
windows_fonts="$WINEPREFIX/drive_c/windows/Fonts"
if [[ ! -f "$WINEPREFIX/system.reg" || ! -d "$windows_fonts" ]]; then
  print -u2 -- "Wine prefix is not initialized: $WINEPREFIX"
  exit 1
fi

font_faces=(
  segoeui.ttf   'Segoe UI'
  segoeuii.ttf  'Segoe UI Italic'
  segoeuib.ttf  'Segoe UI Bold'
  segoeuiz.ttf  'Segoe UI Bold Italic'
  segoeuil.ttf  'Segoe UI Light'
  seguili.ttf   'Segoe UI Light Italic'
  segoeuisl.ttf 'Segoe UI Semilight'
  seguisli.ttf  'Segoe UI Semilight Italic'
  seguisb.ttf   'Segoe UI Semibold'
  seguisbi.ttf  'Segoe UI Semibold Italic'
  seguibl.ttf   'Segoe UI Black'
  seguibli.ttf  'Segoe UI Black Italic'
  seguisym.ttf  'Segoe UI Symbol'
  tahoma.ttf    'Tahoma'
  tahomabd.ttf  'Tahoma Bold'
)
font_key='HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
for (( i=1; i <= ${#font_faces}; i+=2 )); do
  file="${font_faces[i]}"
  face="${font_faces[i+1]}"
  source_file="${source_files[$file]:-}"
  [[ -n "$source_file" ]] || continue
  if ! cmp -s "$source_file" "$windows_fonts/$file"; then
    /usr/bin/install -m 644 "$source_file" "$windows_fonts/$file"
  fi
  wine reg add "$font_key" /v "$face (TrueType)" /t REG_SZ /d "$file" /f >/dev/null
  print -r -- "Installed $face"
done
