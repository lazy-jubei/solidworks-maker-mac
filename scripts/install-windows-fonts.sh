#!/bin/zsh
# Download Segoe UI, or register locally supplied fonts, in an existing Wine prefix.
set -eu
source "${0:A:h}/env.sh"

font_dir="${1:-${SW_WINDOWS_FONTS_DIR:-}}"
usage() {
  print 'Usage: scripts/install-windows-fonts.sh [directory containing segoeui.ttf]'
}
if [[ "${1:-}" == --help ]] && (( $# == 1 )); then
  usage
  exit 0
fi
if (( $# > 1 )); then
  usage >&2
  exit 2
fi
windows_fonts="$WINEPREFIX/drive_c/windows/Fonts"
if [[ ! -f "$WINEPREFIX/system.reg" || ! -d "$windows_fonts" ]]; then
  print -u2 -- "Wine prefix is not initialized: $WINEPREFIX"
  exit 1
fi
if [[ -z "$font_dir" ]]; then
  revision=a89213b7136da6dd5c3638db1f2c6e814c40fa84
  archive_sha256=4093f29b8a5e9efa485e2400b12f88eecf63a96cad33e6a130a0cee56f2bacd5
  mkdir -p "$CACHE/fonts"
  font_work="$(mktemp -d "$CACHE/fonts/segoe.XXXXXXXX")"
  trap 'rm -rf -- "$font_work"' EXIT
  archive="$CACHE/fonts/segoe-ui-$revision.tar.gz"
  archive_valid() {
    [[ -f "$1" && "$(shasum -a 256 "$1" | cut -d' ' -f1)" == "$archive_sha256" ]]
  }
  if ! archive_valid "$archive"; then
    print 'Downloading Segoe UI…'
    curl -fL --retry 3 --connect-timeout 20 --max-time 300 \
      "https://codeload.github.com/mrbvrz/segoe-ui-linux/tar.gz/$revision" \
      -o "$font_work/download.tar.gz"
    if ! archive_valid "$font_work/download.tar.gz"; then
      print -u2 'Segoe UI download failed checksum verification.'
      exit 1
    fi
    mv -- "$font_work/download.tar.gz" "$archive"
  fi
  tar -xzf "$archive" -C "$font_work"
  font_dir="$font_work/segoe-ui-linux-$revision/font"
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
  seguiemj.ttf  'Segoe UI Emoji'
  seguihis.ttf  'Segoe UI Historic'
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
