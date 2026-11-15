#!/bin/zsh
# Build the Intel SolidWorks renderer into a standalone Wine module tree.
set -eu
if (( $# != 3 )); then
    print -u2 'Usage: build-intel-renderer.sh WINE_11_16_SOURCE LLVM_MINGW_BIN NEW_OUTPUT_DIR'
    exit 2
fi
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != x86_64 ||
      "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]]; then
    print -u2 'This renderer build is for Intel macOS.'
    exit 2
fi
wine_source=${1:A}
mingw_bin=${2:A}
output=${3:A}
patches=${0:A:h}/patches
if [[ ! -f "$wine_source/include/wine/unixlib.h" || ! -f "$wine_source/VERSION" ||
      "$(<"$wine_source/VERSION")" != 'Wine version 11.16' ]]; then
    print -u2 'Pass the Wine 11.16 source tree used by the installer.'
    exit 2
fi
for compiler in "$mingw_bin"/{x86_64,i686}-w64-mingw32-clang; do
    [[ -x "$compiler" ]] || { print -u2 "Missing LLVM-MinGW compiler $compiler"; exit 2; }
done
for tool in cmake ninja; do
    command -v "$tool" >/dev/null || { print -u2 "Missing $tool on PATH"; exit 2; }
done
# Reserve the destination before building. Publish the module only after it is complete.
mkdir "$output"
# Upstream's module builder splits object and include paths on spaces.
scratch=$(mktemp -d /private/tmp/sw-intel-renderer.XXXXXXXX) || { rmdir "$output"; exit 1; }
trap 'rm -rf -- "$scratch" "$output/.wine-module"; rmdir -- "$output" 2>/dev/null || true' EXIT
trap 'exit 130' INT TERM
tag=winemetalgl-3.9.0
archive="$scratch/source.tar.gz"
sha=4ad307357ce02bfe95a56f9599294127f9a9697013a1295c8fed531f008a8311
curl --proto '=https' -fL --retry 2 -o "$archive" "https://codeload.github.com/metalsharp/WineMetalGL/tar.gz/refs/tags/$tag"
print -r -- "$sha  $archive" | shasum -a 256 -c -
tar -xzf "$archive" -C "$scratch"
source_dir="$scratch/WineMetalGL-$tag"
ln -s "$wine_source" "$scratch/wine"
export PATH="$mingw_bin:$PATH"
(
    cd "$source_dir"
    git apply "$patches/winemetalgl-radeon.patch"
    git apply "$patches/winemetalgl-early-drawable.patch"
    cmake --preset release
    cmake --build --preset release --target winemetalgl_core --parallel 4
    sh scripts/build-wine-module.sh "$scratch/wine" "$scratch/module"
)
platform="$scratch/module/x86_64-unix"
cp "$source_dir/build/release/libwinemetalgl.dylib" "$platform/"
for image in "$platform"/{libwinemetalgl.dylib,winemetalgl.so}; do
    codesign --force --sign - "$image"
    codesign --verify --strict "$image"
done
(
    cd "$scratch/module"
    shasum -a 256 x86_64-unix/{libwinemetalgl.dylib,winemetalgl.so} \
        {x86_64,i386}-windows/{opengl32.dll,winemetalgl.dll} > SHA256SUMS.txt
)
mkdir "$scratch/package"
mv "$scratch/module"/{x86_64-unix,x86_64-windows,i386-windows,SHA256SUMS.txt} "$scratch/package/"
ditto "$scratch/package" "$output/.wine-module"
mv "$output/.wine-module" "$output/wine-module"
print -r -- "Built Intel WineMetalGL at $output/wine-module"
