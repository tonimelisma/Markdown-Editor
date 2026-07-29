#!/bin/bash
# REQ-099: no EditorTraceEvent case may exist without a production call site. An event that is
# defined and mapped but never recorded reads as coverage in review and produces nothing in a
# run log — worse than not having the event at all.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

failures=0
block="$(awk '/^nonisolated enum EditorTraceEvent/,/^}/' "Markdown Editor/EditorTrace.swift")"
cases="$(printf '%s\n' "$block" | rg -o '^    case (\w+)' -r '$1')"

while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    hits="$(rg -l "\.$name\(|\.$name\b" 'Markdown Editor' \
        --glob '!EditorTrace.swift' --glob '!JSONLinesEditorTrace.swift' || true)"
    if [[ -z "$hits" ]]; then
        printf 'instrumentation-coverage: event never recorded: %s\n' "$name" >&2
        failures=$((failures + 1))
    fi
done <<<"$cases"

if (( failures > 0 )); then
    printf 'instrumentation-coverage: FAILED (%d)\n' "$failures" >&2
    exit 1
fi
printf 'instrumentation-coverage: PASS\n'
