#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'DMG packaging requires macOS.' >&2; exit 1; }
app_dir="$PWD/dist/SoloIsland.app"
dmg_path="$PWD/dist/SoloIsland.dmg"
[[ -x "$app_dir/Contents/MacOS/SoloIsland" ]] || { echo 'Build SoloIsland.app first.' >&2; exit 1; }
[[ -x "$app_dir/Contents/Resources/MediaControl/bin/media-control" ]] || { echo 'The bundled media helper is missing.' >&2; exit 1; }
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/solo-dmg.XXXXXX")"
mounted=false
cleanup() {
    if [[ "$mounted" == true ]]; then
        hdiutil detach "$work_dir/mount" -quiet || hdiutil detach -force "$work_dir/mount" -quiet || true
    fi
    rm -rf "$work_dir"
}
trap cleanup EXIT
mkdir -p "$work_dir/stage" "$work_dir/mount"
ditto "$app_dir" "$work_dir/stage/SoloIsland.app"
ln -s /Applications "$work_dir/stage/Applications"
cat > "$work_dir/stage/Установка.txt" <<'INSTALL'
Solo Island

1. Перетащите SoloIsland.app в папку Applications («Программы»).
2. Извлеките этот диск.
3. Откройте Solo Island из «Программ».

Островок появится у камеры, значок капсулы — в строке меню.
Homebrew, Node.js и компилятор для использования не нужны.

Уведомления разрешаются в настройках приложения.
Для «Не беспокоить» настройте две «Быстрые команды» в разделе настроек.
Сборка локально подписана ad-hoc; нотарификация Apple не выполнена.
INSTALL
# Build a generously sized writable volume first, then compress the closed
# image. Direct srcfolder -> UDZO creation produced an invalid tiny image on a
# hosted macOS runner after adding the pet atlases. Keep both CRC verification
# and the relocated, read-only application checks below.
stage_kib="$(du -sk "$work_dir/stage" | awk '{print $1}')"
image_mib=$(( (stage_kib + 1023) / 1024 + 32 ))
if (( image_mib < 64 )); then image_mib=64; fi
image_valid=false
for attempt in 1 2; do
    hdiutil create -size "${image_mib}m" -layout SPUD -volname 'Solo Island' -fs HFS+ \
        -srcfolder "$work_dir/stage" -format UDRW -ov "$work_dir/writable.dmg"
    hdiutil convert "$work_dir/writable.dmg" -format UDZO -ov -o "$dmg_path"
    if hdiutil verify "$dmg_path"; then image_valid=true; break; fi
    echo "Disk image verification failed on attempt $attempt; rebuilding the generated image." >&2
    rm -f "$dmg_path" "$work_dir/writable.dmg"
done
[[ "$image_valid" == true ]] || { echo 'The generated DMG failed integrity verification.' >&2; exit 1; }
hdiutil attach "$dmg_path" -readonly -nobrowse -mountpoint "$work_dir/mount"
mounted=true
[[ "$(readlink "$work_dir/mount/Applications")" == /Applications ]]
codesign --verify --deep --strict "$work_dir/mount/SoloIsland.app"
"$work_dir/mount/SoloIsland.app/Contents/Resources/MediaControl/bin/media-control" version
# Exercise the relocated helper without a Homebrew layout. null is valid with no media session.
"$work_dir/mount/SoloIsland.app/Contents/Resources/MediaControl/bin/media-control" get --no-artwork
# Framework loading and macOS indexing can briefly retain a read-only volume.
# Only this script's private validation mount is eligible for a forced detach.
for attempt in 1 2 3; do
    if hdiutil detach "$work_dir/mount"; then mounted=false; break; fi
    sleep 1
done
if [[ "$mounted" == true ]]; then
    hdiutil detach -force "$work_dir/mount"
    mounted=false
fi
(cd dist && shasum -a 256 SoloIsland.dmg) > "$PWD/dist/SoloIsland.dmg.sha256"
echo "Installer: $dmg_path"
