#!/bin/bash
# Used only in GitHub Actions. Publish an isolated artifact branch without touching the checkout.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${GITHUB_EVENT_NAME:-}" == push && "${GITHUB_REF:-}" == refs/heads/solo-island ]] || {
    echo 'Artifact publishing is restricted to the solo-island push workflow.' >&2; exit 1;
}
cd "$(dirname "$0")/.."
work_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/solo-publish.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
# Never publish a stale build after a newer source push.
remote_source="$(git ls-remote origin refs/heads/solo-island | cut -f1)"
if [[ "$remote_source" != "$GITHUB_SHA" ]]; then echo 'Newer source revision exists; skipping stale output.'; exit 0; fi
branch=solo-island-builds
parent_commit=""
if git ls-remote --exit-code --heads origin "$branch" > "$work_dir/remote-ref"; then
    git fetch --no-tags origin "refs/heads/$branch"
    parent_commit="$(git rev-parse FETCH_HEAD)"
else
    status=$?
    [[ "$status" == 2 ]] || exit "$status"
fi
export GIT_INDEX_FILE="$work_dir/index"
git read-tree --empty
add_file() {
    local object_id
    object_id="$(git hash-object -w "$1")"
    git update-index --add --cacheinfo 100644 "$object_id" "$2"
}
python3 - <<'PY' > "$work_dir/build-info.json"
import json, os
print(json.dumps({
    'source_commit': os.environ['GITHUB_SHA'],
    'result': os.environ.get('BUILD_RESULT', 'unknown'),
    'run_url': 'https://github.com/' + os.environ['GITHUB_REPOSITORY'] + '/actions/runs/' + os.environ['GITHUB_RUN_ID'],
    'installer': 'SoloIsland.dmg' if os.environ.get('BUILD_RESULT') == 'success' else None
}, ensure_ascii=False, indent=2))
PY
add_file "$work_dir/build-info.json" build-info.json
if [[ -f "${RUNNER_TEMP}/solo-build.log" ]]; then add_file "${RUNNER_TEMP}/solo-build.log" build.log; fi
if [[ "${BUILD_RESULT:-}" == success ]]; then
    [[ -f dist/SoloIsland.dmg ]] || { echo 'Successful build has no DMG.' >&2; exit 1; }
    add_file dist/SoloIsland.dmg SoloIsland.dmg
    if [[ -f dist/SoloIsland-preview.png ]]; then add_file dist/SoloIsland-preview.png preview.png; fi
    for preview in SoloIsland-opening.gif SoloIsland-tasks.png SoloIsland-actions.png SoloIsland-focus.png SoloIsland-files.png SoloIsland-onboarding.png SoloIsland-custom-focus.png SoloIsland-deadline.png SoloIsland-reminder.png SoloIsland-settings.png SoloIsland-web-demo.png SoloIsland-icon.png SoloIsland-focus-motion.gif SoloIsland-focus-motion.json; do
        if [[ -f "dist/$preview" ]]; then add_file "dist/$preview" "$preview"; fi
    done
    # A relative filename makes the checksum file usable after downloading.
    (cd dist && shasum -a 256 SoloIsland.dmg) > "$work_dir/SoloIsland.dmg.sha256"
    add_file "$work_dir/SoloIsland.dmg.sha256" SoloIsland.dmg.sha256
fi
tree_id="$(git write-tree)"
commit_args=("$tree_id" -m "Package Solo Island for ${GITHUB_SHA:0:7}")
if [[ -n "$parent_commit" ]]; then commit_args+=(-p "$parent_commit"); fi
commit_id="$(git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    commit-tree "${commit_args[@]}")"
# No force push. A concurrent publication must fail safely, not overwrite a newer build.
git push origin "$commit_id:refs/heads/$branch"
