#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
    echo "Solo Island requires macOS and the Apple SDK. Run this script on your Mac." >&2
    exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
    echo "Install Apple Command Line Tools first: xcode-select --install" >&2
    exit 1
fi
configuration="${CONFIGURATION:-release}"
app_arch="${SOLO_ARCH:-arm64}"
case "$app_arch" in
    universal) app_arches=(arm64 x86_64) ;;
    arm64|x86_64) app_arches=("$app_arch") ;;
    *) echo "Unsupported build architecture: $app_arch" >&2; exit 1 ;;
esac
build_phase="${SOLO_BUILD_PHASE:-all}"
case "$build_phase" in all|bundle|preview|package) ;; *) echo "Unsupported build phase: $build_phase" >&2; exit 1 ;; esac
app_dir="$PWD/dist/SoloIsland.app"
if [[ "$build_phase" == all ]]; then swift test; fi
if [[ "$build_phase" == all || "$build_phase" == bundle ]]; then
app_binaries=()
bridge_binaries=()
for architecture in "${app_arches[@]}"; do
    swift build -c "$configuration" --arch "$architecture" --product SoloIsland
    swift build -c "$configuration" --arch "$architecture" --product SoloBridge
    binary_dir="$(swift build -c "$configuration" --arch "$architecture" --show-bin-path)"
    app_binaries+=("$binary_dir/SoloIsland")
    bridge_binaries+=("$binary_dir/SoloBridge")
done
# Only replace our generated bundle, never a user-selected path.
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
if [[ "$app_arch" == universal ]]; then
    lipo -create "${app_binaries[@]}" -output "$app_dir/Contents/MacOS/SoloIsland"
    lipo -create "${bridge_binaries[@]}" -output "$app_dir/Contents/MacOS/SoloBridge"
else
    cp "${app_binaries[0]}" "$app_dir/Contents/MacOS/SoloIsland"
    cp "${bridge_binaries[0]}" "$app_dir/Contents/MacOS/SoloBridge"
fi
chmod 755 "$app_dir/Contents/MacOS/SoloIsland" "$app_dir/Contents/MacOS/SoloBridge"
lipo "$app_dir/Contents/MacOS/SoloBridge" -verify_arch "${app_arches[@]}"
codesign --force --sign - "$app_dir/Contents/MacOS/SoloBridge"
lipo "$app_dir/Contents/MacOS/SoloIsland" -verify_arch "${app_arches[@]}"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
rm -rf "$app_dir/Contents/Resources/AgentPets"
cp -R Resources/AgentPets "$app_dir/Contents/Resources/AgentPets"
rm -rf "$app_dir/Contents/Resources/BrowserExtension"
cp -R Resources/BrowserExtension "$app_dir/Contents/Resources/BrowserExtension"
/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app_dir/Contents/Info.plist" >/dev/null
iconset_dir="$(mktemp -d "${TMPDIR:-/tmp}/solo-island-icons.XXXXXX")/AppIcon.iconset"
trap 'rm -rf "${iconset_dir%/AppIcon.iconset}"' EXIT
swift scripts/make-icon.swift "$iconset_dir"
cp "$iconset_dir/icon_256x256.png" "$PWD/dist/SoloIsland-icon.png"
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/AppIcon.icns"
bash scripts/bundle-media.sh
# Local ad-hoc signing; no Apple credentials are needed. Not a notarized distribution.
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict --verbose=2 "$app_dir"
ditto -c -k --keepParent "$app_dir" "$PWD/dist/SoloIsland-macOS.zip"
fi
if [[ "$build_phase" == all || "$build_phase" == preview ]]; then
rm -f "$PWD/dist/SoloIsland-quit-check.json"
if [[ "${SOLO_RECORD_FOOTAGE:-0}" == 1 ]]; then
    "$app_dir/Contents/MacOS/SoloIsland" --render-preview "$PWD/dist/SoloIsland-preview.png"
else
    "$app_dir/Contents/MacOS/SoloIsland" --render-preview "$PWD/dist/SoloIsland-preview.png" --verify-only
fi
[[ -s "$PWD/dist/SoloIsland-quit-check.json" ]] || { echo 'Native quit button smoke test did not finish.' >&2; exit 1; }
fi
if [[ "$build_phase" == all || "$build_phase" == package ]]; then bash scripts/package-dmg.sh; fi
echo "Built: $app_dir"
echo "Archive: $PWD/dist/SoloIsland-macOS.zip"
