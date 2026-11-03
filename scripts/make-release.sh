#!/bin/zsh
# Package only committed, reviewed files, never a live prefix or working tree.
set -eu
cd "${0:A:h:h}"
version="${1:?usage: make-release.sh vMAJOR.MINOR.PATCH}"
[[ "$version" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'Invalid release version'; exit 2; }
[[ -z "$(git status --porcelain)" ]] || { print -u2 'Commit changes before packaging'; exit 1; }
python3 scripts/check-release.py
folder="dist/$version"
mkdir -p "$folder"
archive="solidworks-maker-mac-$version.tar.gz"
git archive --format=tar --prefix="solidworks-maker-mac-$version/" HEAD | gzip -n > "$folder/$archive"
( cd "$folder"; shasum -a 256 "$archive" > SHA256SUMS; shasum -a 256 -c SHA256SUMS )
print -r -- "$folder/$archive"
