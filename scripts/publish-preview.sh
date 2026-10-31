#!/bin/bash
# Save a test installer in its own preview branch; never update public releases.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${GITHUB_EVENT_NAME:-}" == push && "${GITHUB_REF:-}" == refs/heads/preview/* ]] || {
    echo 'Preview output is restricted to preview branch push workflows.' >&2; exit 1;
}
cd "$(dirname "$0")/.."
branch_ref="$GITHUB_REF"
remote_source="$(git ls-remote origin "$branch_ref" | cut -f1)"
if [[ "$remote_source" != "$GITHUB_SHA" ]]; then echo 'Newer preview source exists; skipping stale output.'; exit 0; fi
work_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/solo-preview-publish.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
export GIT_INDEX_FILE="$work_dir/index"
# Keep source files intact, but replace all output from a preceding preview.
git read-tree "$GITHUB_SHA"
git ls-files -z -- .preview-build | git update-index --force-remove -z --stdin
add_file() {
    local object_id
    object_id="$(git hash-object -w "$1")"
    git update-index --add --cacheinfo 100644 "$object_id" ".preview-build/$2"
}
python3 - <<'PY' > "$work_dir/build-info.json"
import json, os
print(json.dumps({
    'source_commit': os.environ['GITHUB_SHA'],
    'result': os.environ.get('BUILD_RESULT', 'unknown'),
    'run_url': 'https://github.com/' + os.environ['GITHUB_REPOSITORY'] + '/actions/runs/' + os.environ['GITHUB_RUN_ID'],
    'installer': 'SoloIsland.dmg' if os.environ.get('BUILD_RESULT') == 'success' else None,
    'channel': 'preview'
}, indent=2))
PY
add_file "$work_dir/build-info.json" build-info.json
if [[ -f "${RUNNER_TEMP}/solo-build.log" ]]; then add_file "${RUNNER_TEMP}/solo-build.log" build.log; fi
if [[ -f dist/SoloIsland-interaction-debug.png ]]; then add_file dist/SoloIsland-interaction-debug.png SoloIsland-interaction-debug.png; fi
if [[ "${BUILD_RESULT:-}" == success ]]; then
    [[ -f dist/SoloIsland.dmg ]] || { echo 'Successful preview has no DMG.' >&2; exit 1; }
    add_file dist/SoloIsland.dmg SoloIsland.dmg
    (cd dist && shasum -a 256 SoloIsland.dmg) > "$work_dir/SoloIsland.dmg.sha256"
    add_file "$work_dir/SoloIsland.dmg.sha256" SoloIsland.dmg.sha256
fi
# Keep named synthetic captures available to diagnose a failed native check.
    if [[ -f dist/SoloIsland-preview.png ]]; then add_file dist/SoloIsland-preview.png preview.png; fi
    for preview in SoloIsland-tasks.png SoloIsland-actions.png SoloIsland-focus.png SoloIsland-files.png SoloIsland-onboarding.png SoloIsland-custom-focus.png SoloIsland-deadline.png SoloIsland-reminder.png SoloIsland-settings.png SoloIsland-web-demo.png SoloIsland-icon.png SoloIsland-music-compact.png SoloIsland-tasks-compact.png SoloIsland-focus-compact.png SoloIsland-settings-compact.png SoloIsland-settings-appearance.png SoloIsland-music-empty.png SoloIsland-tasks-empty.png SoloIsland-music-error.png SoloIsland-notch-music.png SoloIsland-notch-paused.png SoloIsland-notch-focus.png SoloIsland-notch-focus-paused.png SoloIsland-notch-combined.png; do
        if [[ -f "dist/$preview" ]]; then add_file "dist/$preview" "$preview"; fi
    done
tree_id="$(git write-tree)"
commit_id="$(git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    commit-tree "$tree_id" -p "$GITHUB_SHA" -m "Save preview installer for ${GITHUB_SHA:0:7} [skip ci]")"
# A source change racing this build is protected by a normal fast-forward push.
git push origin "$commit_id:$branch_ref"
