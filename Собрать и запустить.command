#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ! bash scripts/setup-mac.sh; then
    echo ""
    echo "Не удалось завершить сборку. Скопируйте ошибку выше и пришлите её в чат."
    read -r -p "Нажмите Enter, чтобы закрыть окно…" _
    exit 1
fi
