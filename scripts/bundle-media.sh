#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
    echo "The media helper must be built with the macOS SDK." >&2; exit 1
fi
command -v cmake >/dev/null || { echo 'Build dependency missing: cmake' >&2; exit 1; }
# v0.7.7. Both this revision and its adapter submodule are pinned, not a moving branch.
media_revision=3cfd5dcf78e7a619f7a42a3e2f29b06eb41027ea
app_arch="${SOLO_ARCH:-arm64}"
helper_dir="$PWD/dist/SoloIsland.app/Contents/Resources/MediaControl"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/solo-media.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
git init -q "$work_dir/source"
git -C "$work_dir/source" remote add origin https://github.com/ungive/media-control.git
git -C "$work_dir/source" fetch --depth 1 origin "$media_revision"
git -C "$work_dir/source" checkout --detach FETCH_HEAD
[[ "$(git -C "$work_dir/source" rev-parse HEAD)" == "$media_revision" ]]
git -C "$work_dir/source" submodule update --init --recursive --depth 1
cmake -S "$work_dir/source" -B "$work_dir/build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_INSTALL_PREFIX="$helper_dir"
cmake --build "$work_dir/build" --parallel 2
# Replace only the generated helper tree, so removed upstream files cannot linger.
rm -rf "$helper_dir"
cmake --install "$work_dir/build"
cp "$work_dir/source/mediaremote-adapter/LICENSE" "$helper_dir/MediaRemoteAdapter-LICENSE.txt"
printf '%s\n' 'media-control v0.7.7 — BSD 3-Clause' \
    'Copyright (c) 2025 Jonas van den Berg' \
    'https://github.com/ungive/media-control' \
    'License terms: MediaRemoteAdapter-LICENSE.txt in this directory.' > "$helper_dir/NOTICE.txt"
printf '%s\n' "$media_revision" > "$helper_dir/source-revision.txt"
framework="$helper_dir/Frameworks/MediaRemoteAdapter.framework"
client="$helper_dir/lib/media-control/MediaRemoteAdapterTestClient"
lipo "$framework/MediaRemoteAdapter" -verify_arch "$app_arch"
lipo "$client" -verify_arch "$app_arch"
# No dependency may accidentally point at the builder's Homebrew installation.
linkage="$(otool -L "$framework/MediaRemoteAdapter" "$client")"
if printf '%s\n' "$linkage" | grep -E '^[[:space:]]+/(opt/homebrew|usr/local|Users)/'; then
    echo 'The helper contains a non-system dynamic dependency.' >&2; exit 1
fi
codesign --force --sign - "$framework"
codesign --force --sign - "$client"
codesign --verify --strict "$framework"
codesign --verify --strict "$client"
"$helper_dir/bin/media-control" version
