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
    if [[ "$mounted" == true ]]; then hdiutil detach "$work_dir/mount" -quiet || true; fi
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
hdiutil create -volname 'Solo Island' -fs HFS+ -srcfolder "$work_dir/stage" -format UDZO -ov "$dmg_path"
hdiutil verify "$dmg_path"
hdiutil attach "$dmg_path" -readonly -nobrowse -mountpoint "$work_dir/mount"
mounted=true
[[ "$(readlink "$work_dir/mount/Applications")" == /Applications ]]
codesign --verify --deep --strict "$work_dir/mount/SoloIsland.app"
"$work_dir/mount/SoloIsland.app/Contents/Resources/MediaControl/bin/media-control" version
# Exercise the relocated helper without a Homebrew layout. null is valid with no media session.
"$work_dir/mount/SoloIsland.app/Contents/Resources/MediaControl/bin/media-control" get --no-artwork
hdiutil detach "$work_dir/mount"
mounted=false
(cd dist && shasum -a 256 SoloIsland.dmg) > "$PWD/dist/SoloIsland.dmg.sha256"
echo "Installer: $dmg_path"
