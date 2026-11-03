#!/bin/zsh
# Create (first run) and mount the case-insensitive HFS+ image on the share.
set -eu
source "${0:A:h}/env.sh"
mount_state="$(python3 "${0:A:h}/tools/image-mount-state.py" "$IMAGE" "$VOL")"
mkdir -p "$CACHE"
if [[ "$mount_state" == unmounted && ! -d "$IMAGE" ]]; then
  # hdiutil create fails directly on SMB ("RPC version wrong"); an empty image is
  # only ~30 MB, so create it locally and move it to the share.
  tmpd="$(mktemp -d /private/tmp/swwine.XXXXXX)"
  # HFS+, not APFS: an APFS image on this share starts failing every file create
  # with "Operation not supported" shortly after mounting.
  hdiutil create -size "$IMAGE_SIZE" -type SPARSEBUNDLE -fs HFS+ -volname "${VOL:t}" "$tmpd/${IMAGE:t}"
  mv "$tmpd/${IMAGE:t}" "$IMAGE"
  rmdir "$tmpd"
fi
if [[ "$mount_state" == unmounted ]]; then
  hdiutil attach "$IMAGE" -mountpoint "$VOL" -nobrowse -noverify -noautofsck -owners on
fi
mount_state="$(python3 "${0:A:h}/tools/image-mount-state.py" "$IMAGE" "$VOL")"
[[ "$mount_state" == mounted ]] || { print -u2 'Disk image did not mount at the configured location.'; exit 1; }
mkdir -p "$VOL/tmp" "$VOL/bin"
df -h "$VOL"
