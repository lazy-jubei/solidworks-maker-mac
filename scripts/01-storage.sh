#!/bin/zsh
# Create (first run) and mount the case-insensitive HFS+ image on the share.
set -eu
source "${0:A:h}/env.sh"
mkdir -p "$CACHE"
if [[ ! -d "$IMAGE" ]]; then
  # hdiutil create fails directly on SMB ("RPC version wrong"); an empty image is
  # only ~30 MB, so create it locally and move it to the share.
  tmpd="$(mktemp -d /private/tmp/swwine.XXXXXX)"
  # HFS+, not APFS: an APFS image on this share starts failing every file create
  # with "Operation not supported" shortly after mounting.
  hdiutil create -size "$IMAGE_SIZE" -type SPARSEBUNDLE -fs HFS+ -volname "${VOL:t}" "$tmpd/${IMAGE:t}"
  mv "$tmpd/${IMAGE:t}" "$IMAGE"
  rmdir "$tmpd"
fi
if [[ ! -d "$VOL" ]]; then
  hdiutil attach "$IMAGE" -nobrowse -noverify -noautofsck -owners on
fi
mkdir -p "$VOL/tmp" "$VOL/bin"
df -h "$VOL"
