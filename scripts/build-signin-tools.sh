#!/bin/zsh
# Compile the explicitly targeted login-window helpers; no credentials involved.
set -eu
source "${0:A:h}/env.sh"
mkdir -p "$VOL/tools"
for name in ExistingCad WinInput WebViewWindow ConfirmDialog WinHide SwSmoke SwReopen SwOperations SwDocumentOps SwInteractive SwReady SwWaitCommit SwDimensionRegression SwUi SwFps; do
  src="$(winepath -w "$ROOT/scripts/tools/$name.cs")"
  out="$(winepath -w "$VOL/tools/$name.exe")"
  wine 'C:\windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' \
      /nologo /platform:x64 /target:exe "/out:$out" "$src"
  # The launcher rebuilds a helper whose source no longer matches this stamp.
  shasum -a 256 "$ROOT/scripts/tools/$name.cs" | cut -d ' ' -f 1 > "$VOL/tools/$name.source.sha256"
done
