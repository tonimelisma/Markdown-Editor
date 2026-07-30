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

# Strip line comments, block comments, and string-literal contents into scratch copies before
# searching. A raw text scan of the real source would count a call site that exists only in a
# comment or a string literal (dead reference, never executed) as production coverage — this is
# the gap a real Swift parser would not have, and the reason for the extra step below.
#
# strip-swift-lexical-noise.pl is a small stateful scanner, not a single regex: Swift block
# comments nest (`/* outer /* inner */ still commented */`), and a non-greedy
# `s{/\*.*?\*/}{}gs` stops at the first `*/`, leaving the rest of a nested comment — including
# any fake call site inside it — visible to the search below.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
while IFS= read -r -d '' file; do
    rel="${file#Markdown Editor/}"
    dest="$scratch/$rel"
    mkdir -p "$(dirname "$dest")"
    perl "$(dirname "$0")/strip-swift-lexical-noise.pl" <"$file" >"$dest"
done < <(find 'Markdown Editor' -name '*.swift' \
    ! -name 'EditorTrace.swift' ! -name 'JSONLinesEditorTrace.swift' -print0)

while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    # Anchored on "trace?.record(" / "trace.record(", not a bare "."$name substring: every real
    # EditorTraceSink.record call site in this codebase is made through a property literally
    # named `trace`, which is the one thing that reliably distinguishes it from an unrelated
    # same-named DiagnosticEventName/DiagnosticLog.record call (DiagnosticLog.shared?.record(...)
    # is not reached via a `trace` property). A bare substring match would report a case as
    # "covered" merely because some other symbol happens to share its name.
    hits="$(rg -Uo "trace\??\.record\(\s*\.$name(\(|\b)" "$scratch" || true)"
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
