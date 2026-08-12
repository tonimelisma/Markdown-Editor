#!/bin/bash
# REQ-088: the build configurations must keep complete Swift concurrency checking enabled.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
settings_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --settings-file) settings_file="$2"; shift 2 ;;
        *) echo "usage: check-concurrency-settings.sh [--settings-file FILE]" >&2; exit 2 ;;
    esac
done

if [[ -n "$settings_file" ]]; then
    settings="$(<"$settings_file")"
else
    settings=""
    for configuration in Debug Release; do
        for target in 'Markdown Editor' 'Markdown EditorTests'; do
            settings+="$(xcodebuild -project "$repo_root/Markdown Editor.xcodeproj" \
                -target "$target" -configuration "$configuration" -showBuildSettings 2>/dev/null)\n"
        done
    done
fi

for configuration in Debug Release; do
    grep -q "CONFIGURATION = $configuration" <<<"$settings" || {
        echo "concurrency-settings: missing $configuration configuration" >&2
        exit 1
    }
done

strict_count="$(grep -c 'SWIFT_STRICT_CONCURRENCY = complete' <<<"$settings" || true)"
if (( strict_count < 4 )); then
    echo "concurrency-settings: expected complete concurrency checking on app and test targets in Debug and Release (found $strict_count)" >&2
    exit 1
fi

echo "concurrency-settings: PASS (complete concurrency checking observed in Debug and Release app/test settings)"
