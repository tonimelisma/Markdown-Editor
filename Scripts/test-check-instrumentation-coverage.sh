#!/bin/bash
# COR-58 / REQ-135: hermetic fixtures for observed trace-vocabulary coverage.
set -euo pipefail

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
cases="$root/cases.txt"
exemptions="$root/exemptions.md"
logs="$root/logs"
mkdir -p "$logs"
printf 'alpha\nbeta\ngamma\n' > "$cases"
cat > "$exemptions" <<'EOF'
| Event | Reason | Removal plan |
| --- | --- | --- |
| `gamma` | terminal-only fixture route is not exercised by this run | COR-58 behavioral route |
EOF
gate="$(dirname "$0")/check-instrumentation-coverage.sh"
write_log() {
    local path="$1"; shift
    : > "$path"
    for event in "$@"; do
        printf '{"v":2,"ev":"%s"}\n' "$event" >> "$path"
    done
}
expect_fail() {
    if "$@" >/dev/null 2>&1; then
        echo "expected failure: $*" >&2
        exit 1
    fi
}

write_log "$logs/complete.jsonl" alpha beta
("$gate" --cases-file "$cases" --exemptions "$exemptions" --log-dir "$logs") >/dev/null

write_log "$logs/missing.jsonl" alpha
expect_fail "$gate" --cases-file "$cases" --exemptions "$exemptions" --log-dir "$logs/missing.jsonl"

: > "$logs/empty.jsonl"
expect_fail "$gate" --cases-file "$cases" --exemptions "$exemptions" --log-dir "$logs/empty.jsonl"

write_log "$logs/unknown.jsonl" alpha beta delta
expect_fail "$gate" --cases-file "$cases" --exemptions "$exemptions" --log-dir "$logs/unknown.jsonl"

# Rehearsal of the COR-44 defeat: a nil-bound source call cannot add an emitted event. The new
# gate ignores that source text and therefore still rejects the observed log.
printf 'let trace: (any EditorTraceSink)? = nil\ntrace?.record(.beta)\n' > "$root/defeated.swift"
write_log "$logs/rehearsal.jsonl" alpha
expect_fail "$gate" --cases-file "$cases" --exemptions "$exemptions" --log-dir "$logs/rehearsal.jsonl"

echo "check-instrumentation-coverage fixtures: PASS"
