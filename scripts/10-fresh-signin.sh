#!/bin/zsh
# Official launcher with the tested WebView2 software-painting workaround.
# Requires the patched Wine build, DXMT v0.80 and helpers in $VOL/tools.
# Enter credentials in the vendor's form; this script never reads them.
set -eu
source "${0:A:h}/env.sh"
for helper in ConfirmDialog WebViewWindow WinInput ExistingCad; do
  [[ -f "$VOL/tools/$helper.exe" ]] || { print -u2 "Missing $VOL/tools/$helper.exe (compile scripts/tools/$helper.cs with .NET Framework64 csc.exe)"; exit 1; }
done
export SW_REPORT_STANDARD_INTEGRITY=1
# Browser-local native overrides come from install-dxmt.sh. Keep CAD's D3D
# libraries original; a global d3d11/dxgi override defeated that isolation.
export WINEDLLOVERRIDES='winemetal=b'
export DXMT_LOG_LEVEL=warn
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS='--disable-gpu --in-process-gpu --disable-direct-composition --disable-gpu-compositing --disable-features=RemoveRedirectionBitmap,ForceSWDCompWhenDCompFallbackRequired --use-angle=d3d11 --ignore-gpu-blocklist --no-sandbox'
# Wine's HTTP Basic prompt is spurious for this IAM host. Cancel only that exact
# host's prompt. Detach only the official cross-process login browser to avoid
# the Mac driver's foreign-parent GDI painting failure. No credential handling.
exec python3 "${0:A:h}/tools/launch-once.py" "$VOL/tools" "${0:A:h}/run-solidworks.sh"
