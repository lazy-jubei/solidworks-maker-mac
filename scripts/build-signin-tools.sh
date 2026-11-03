#!/bin/zsh
# Compile the explicitly targeted login-window helpers; no credentials involved.
set -eu
source "${0:A:h}/env.sh"
mkdir -p "$VOL/tools"
for name in WinInput WebViewWindow ConfirmDialog SwSmoke SwReopen SwOperations SwDocumentOps SwInteractive SwReady SwUi SwFps; do
  src="$(winepath -w "$ROOT/scripts/tools/$name.cs")"
  out="$(winepath -w "$VOL/tools/$name.exe")"
  wine 'C:\windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' \
      /nologo /platform:x64 /target:exe "/out:$out" "$src"
done
