#!/bin/zsh
# Install SolidWorks silently from a saved copy of the installer, without the dashboard.
# First install from the dashboard once, then save its media with: 07-install-offline.sh --save <prefix>
# The saved answers file holds your tenant, so the copy is specific to your account.
set -eu
source "${0:A:h}/env.sh"
SAVE="$CACHE/sw-media"
MEDIA=SOLIDWORKS_3DEXP_Desktop.Full.Windows64
if [[ "${1:-}" == "--save" ]]; then
  FROM="$2/drive_c"
  mkdir -p "$SAVE"
  [[ -d "$SAVE/$MEDIA" ]] || cp -R "$FROM/ziptest/ref/$MEDIA" "$SAVE/"
  [[ -d "$SAVE/win_b64" ]] || cp -R "$FROM/ProgramData/DassaultSystemes/3DEXPERIENCELauncher/defaultDataStore/Cafs/R428/428.6.9/FULL/CODE/win_b64" "$SAVE/"
  cp "$FROM/Program Files/Dassault Systemes/SOLIDWORKS 3DEXPERIENCE R2026x/InstallData/UserIntentions_CODE.xml" "$SAVE/"
  du -sh "$SAVE"
  exit 0
fi
[[ -d "$SAVE/win_b64" ]] || { echo "no saved media in $SAVE"; exit 1; }
DRIVE="$WINEPREFIX/drive_c"
# A failed MSI rollback can delete this folder, and the next install then stops.
mkdir -p "$DRIVE/users/Public/Documents" "$DRIVE/swmedia"
rm -rf "${DRIVE:?}/swmedia/$MEDIA"
cp -R "$SAVE/$MEDIA" "$DRIVE/swmedia/"
cp "$SAVE/UserIntentions_CODE.xml" "$DRIVE/swmedia/"
# The installer reads its packages from CAFS next to the media.
mkdir -p "$DRIVE/swmedia/$MEDIA/1/CAFS/CODE"
ln -sfn "$SAVE/win_b64" "$DRIVE/swmedia/$MEDIA/1/CAFS/CODE/win_b64"
cd "$DRIVE/swmedia/$MEDIA/1"
# setup.exe's manifest requests elevation, which the installer requires on Windows 11.
wine setup.exe --silent 'C:\swmedia\UserIntentions_CODE.xml'
# setup.exe returns once it has handed off to the elevated installer.
while pgrep -f DSYInsAppli >/dev/null; do /bin/sleep 15; done
