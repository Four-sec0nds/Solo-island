#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
    echo "Run this script on macOS." >&2; exit 1
fi
if ! command -v brew >/dev/null 2>&1; then
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    else
        echo "Homebrew is required: https://brew.sh" >&2; exit 1
    fi
fi
if ! xcrun --find swift >/dev/null 2>&1; then
    echo "Install Command Line Tools with: xcode-select --install" >&2
    echo "After installation, run this script again." >&2
    exit 1
fi
brew list --formula media-control >/dev/null 2>&1 || brew install media-control
media_control="$(brew --prefix)/bin/media-control"
"$media_control" version
bash scripts/build.sh
open "$PWD/dist/SoloIsland.app"
