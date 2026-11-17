#!/bin/zsh
# Official launcher with the tested WebView2 software-painting workaround.
# Requires the patched Wine build, DXMT v0.80 and helpers in $VOL/tools.
# Enter credentials in the vendor's form; this script never reads them.
set -eu
source "${0:A:h}/env.sh"
# A plain Update refreshes scripts only, so a helper built by an older release keeps its old
# behaviour (the sign-in page once sat in the screen corner, leaving the login window blank).
# Rebuild any helper whose shipped source changed; keep the existing copy if that fails.
for helper in ConfirmDialog WebViewWindow WinInput ExistingCad; do
  source_file="${0:A:h}/tools/$helper.cs"
  [[ -f "$source_file" ]] || continue
  sum=$(shasum -a 256 "$source_file" | cut -d ' ' -f 1)
  stamp="$VOL/tools/$helper.source.sha256"
  [[ -f "$VOL/tools/$helper.exe" && "$(cat "$stamp" 2>/dev/null)" == "$sum" ]] && continue
  mkdir -p "$VOL/tools"
  if WINEDEBUG=-all wine 'C:\windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' /nologo /platform:x64 \
       /target:exe "/out:$(winepath -w "$VOL/tools/$helper.new.exe")" "$(winepath -w "$source_file")" >/dev/null 2>&1 &&
     [[ -s "$VOL/tools/$helper.new.exe" ]]; then
    mv -f "$VOL/tools/$helper.new.exe" "$VOL/tools/$helper.exe"
    print -r -- "$sum" > "$stamp"
  else
    rm -f "$VOL/tools/$helper.new.exe"
    print -u2 "Could not rebuild $helper.exe; using the existing copy."
  fi
done
for helper in ConfirmDialog WebViewWindow WinInput ExistingCad; do
  [[ -f "$VOL/tools/$helper.exe" ]] || { print -u2 "Missing $VOL/tools/$helper.exe (compile scripts/tools/$helper.cs with .NET Framework64 csc.exe)"; exit 1; }
done
# The monitor can leave the browser embedded only with the matching Wine modules.
unset SW_MAC_EMBEDDED_SIGNIN
if [[ "${SW_EMBEDDED_SIGNIN:-0}" == 1 ]]; then
  if (cd "$WINE_APP/Contents/Resources/wine/lib/wine/x86_64-unix" &&
      [[ -f embedded-signin.sha256 ]] &&
      shasum -a 256 win32u.so winemac.so | cmp -s - embedded-signin.sha256); then
    export SW_MAC_EMBEDDED_SIGNIN=1
  else
    print -u2 'Embedded sign-in modules are missing or out of date. Using the existing login workaround.'
  fi
fi
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
