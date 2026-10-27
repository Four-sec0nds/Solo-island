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
swift test
swift build -c "$configuration" --arch "$app_arch" --product SoloIsland
binary_dir="$(swift build -c "$configuration" --arch "$app_arch" --show-bin-path)"
app_dir="$PWD/dist/SoloIsland.app"
# Only replace our generated bundle, never a user-selected path.
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/SoloIsland" "$app_dir/Contents/MacOS/SoloIsland"
lipo "$app_dir/Contents/MacOS/SoloIsland" -verify_arch "$app_arch"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app_dir/Contents/Info.plist" >/dev/null
iconset_dir="$(mktemp -d "${TMPDIR:-/tmp}/solo-island-icons.XXXXXX")/AppIcon.iconset"
trap 'rm -rf "${iconset_dir%/AppIcon.iconset}"' EXIT
swift scripts/make-icon.swift "$iconset_dir"
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/AppIcon.icns"
bash scripts/bundle-media.sh
# Local ad-hoc signing; no Apple credentials are needed. Not a notarized distribution.
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict --verbose=2 "$app_dir"
ditto -c -k --keepParent "$app_dir" "$PWD/dist/SoloIsland-macOS.zip"
"$app_dir/Contents/MacOS/SoloIsland" --render-preview "$PWD/dist/SoloIsland-preview.png"
bash scripts/package-dmg.sh
echo "Built: $app_dir"
echo "Archive: $PWD/dist/SoloIsland-macOS.zip"
