#!/bin/zsh
# Package only committed, reviewed files, never a live prefix or working tree.
set -eu
cd "${0:A:h:h}"
version="${1:?usage: make-release.sh vMAJOR.MINOR.PATCH}"
[[ "$version" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'Invalid release version'; exit 2; }
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { print -u2 'Commit tracked changes before packaging'; exit 1; }
python3 scripts/check-release.py
folder="dist/$version"
mkdir -p "$folder"
archive="solidworks-maker-mac-$version.tar.gz"
manifest_work="$(mktemp -d /private/tmp/sw-release.XXXXXXXX)"
trap 'rm -rf -- "$manifest_work"' EXIT
git ls-tree -r --name-only HEAD | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().splitlines(), indent=2))' > "$manifest_work/.sw-project-files.json"
git archive --format=tar --prefix="solidworks-maker-mac-$version/" --add-file="$manifest_work/.sw-project-files.json" HEAD | gzip -n > "$folder/$archive"
# Stable asset name lets the one-command installer fetch the latest published release.
cp "$folder/$archive" "$folder/solidworks-maker-mac.tar.gz"
( cd "$folder"; shasum -a 256 "$archive" solidworks-maker-mac.tar.gz > SHA256SUMS; shasum -a 256 -c SHA256SUMS )
print -r -- "$folder/$archive"
