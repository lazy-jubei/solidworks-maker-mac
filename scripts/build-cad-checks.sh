#!/bin/zsh
# Compile modeling checks after installing SOLIDWORKS. Does not run CAD tests.
set -eu
source "${0:A:h}/env.sh"
const_dll="${SW_SWCONST_DLL:-}"
if [[ -z "$const_dll" ]]; then
  candidates=("$WINEPREFIX"/drive_c/Program\ Files/Dassault\ Systemes/SOLIDWORKS*/SOLIDWORKS/api/redist/SolidWorks.Interop.swconst.dll(N))
  if (( ${#candidates} != 1 )); then
    print -u2 'Expected one installed SOLIDWORKS API constants assembly; set SW_SWCONST_DLL to its macOS file path.'
    exit 1
  fi
  const_dll="$candidates[1]"
fi
[[ -f "$const_dll" ]] || { print -u2 'SW_SWCONST_DLL does not name a file'; exit 1; }
mkdir -p "$VOL/tools"
const_windows="$(winepath -w "$const_dll")"
for name in SwExportOps SwEdgeOps; do
  src="$(winepath -w "$ROOT/scripts/tools/$name.cs")"
  out="$(winepath -w "$VOL/tools/$name.exe")"
  wine 'C:\windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' \
    /nologo /platform:x64 /target:exe "/reference:$const_windows" "/out:$out" "$src"
done
