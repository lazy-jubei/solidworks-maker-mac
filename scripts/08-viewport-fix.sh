#!/bin/zsh
# Build the optional Mac-driver layout helper. Requires .NET from 03-prefix.sh.
set -eu
source "${0:A:h}/env.sh"
mkdir -p "$VOL/tools"
SRC="$(winepath -w "${0:A:h}/tools/SwViewportFix.cs")"
OUT="$(winepath -w "$VOL/tools/SwViewportFix.exe")"
wine 'C:\windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' \
    /nologo /platform:x64 /target:winexe "/out:$OUT" "$SRC"
print 'Experimental viewport helper built. Automatic use is disabled because it can crash sketch editing.'
