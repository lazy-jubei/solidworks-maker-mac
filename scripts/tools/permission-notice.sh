#!/bin/zsh
# Shown when Wine's startup stalls. Starting Wine reads every mapped drive, and macOS holds that
# read while it asks for access to a removable or network volume. The prompt can open behind
# other windows or on another display, and it returns whenever an update re-signs the app.
# The caller stops this process, which closes the notice, once Wine carries on.
title='SolidWorks is still starting'
message='macOS may be asking whether SolidWorks (Wine) can access files, for example on a removable or network volume. The request can be hidden behind other windows or on another display. Allow it to continue, or turn it on in System Settings > Privacy & Security > Files & Folders.'
if [[ -n "${SW_LAUNCHER_NOTICE:-}" ]]; then
  # macOS keeps a background script's alert from coming forward, so the Finder app shows it:
  # it displays the notice while this file exists.
  waiter=''
  trap 'kill $waiter 2>/dev/null; rm -f -- "$SW_LAUNCHER_NOTICE"; exit 0' TERM INT
  print -r -- "$title"$'\n'"$message" > "$SW_LAUNCHER_NOTICE.new" && mv -f -- "$SW_LAUNCHER_NOTICE.new" "$SW_LAUNCHER_NOTICE"
  sleep 900 &
  waiter=$!
  wait $waiter
  rm -f -- "$SW_LAUNCHER_NOTICE"
  exit 0
fi
exec osascript -e 'tell me to activate' -e "display alert \"$title\" message \"$message\" giving up after 900" > /dev/null 2>&1
