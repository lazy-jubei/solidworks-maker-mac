#!/bin/zsh
# Open the dashboard in a private browser that identifies as Windows, so it offers Install.
# Uses a pinned Chrome for Testing on the share, so your own browsers and profiles aren't touched.
# --use-mock-keychain stops macOS asking for your keychain password. The profile is deleted on exit,
# and stopping this script closes the browser.
# Only needed once per account: after that, 07-install-offline.sh needs no browser.
# Usage: open-dashboard.sh <dashboard url>
set -eu
source "${0:A:h}/env.sh"
CFT_VERSION="156.0.8078.80"
# Select the native browser even if this script runs under Rosetta on Apple Silicon.
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]]; then
  CFT_PLATFORM=mac-arm64
else
  case "$(uname -m)" in
    x86_64) CFT_PLATFORM=mac-x64 ;;
    *) print -u2 'The dashboard browser requires an Intel or Apple Silicon Mac.'; exit 1 ;;
  esac
fi
D="$CACHE/chrome-for-testing"
ZIP="$D/chrome-$CFT_PLATFORM.zip"
APP="$D/chrome-$CFT_PLATFORM/Google Chrome for Testing.app"
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36'
mkdir -p "$D"
[[ -f "$ZIP" ]] || curl -fL -o "$ZIP" "https://storage.googleapis.com/chrome-for-testing-public/$CFT_VERSION/$CFT_PLATFORM/chrome-$CFT_PLATFORM.zip"
if [[ ! -d "$APP" ]]; then
  ( cd "$D" && ditto -xk "$ZIP" . )
  xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
fi
PROFILE="$(mktemp -d "$VOL/tmp/dashboard-profile.XXXXXX")"
browser=''
# Stopping this script (the installer does when it no longer needs the browser) closes it.
trap 'if [[ -n "$browser" ]]; then kill "$browser" 2>/dev/null; wait "$browser" 2>/dev/null; fi; rm -rf "$PROFILE"' EXIT
trap 'exit 143' HUP INT TERM
# Don't offer to keep the account password: with the mock keychain it wouldn't be protected.
mkdir -p "$PROFILE/Default"
print -r -- '{"credentials_enable_service":false,"profile":{"password_manager_enabled":false}}' > "$PROFILE/Default/Preferences"
"$APP/Contents/MacOS/Google Chrome for Testing" --use-mock-keychain --no-first-run --no-default-browser-check \
  --user-data-dir="$PROFILE" --user-agent="$UA" --load-extension="${0:A:h}/tools/windows-identity" "$1" &
browser=$!
wait "$browser"
