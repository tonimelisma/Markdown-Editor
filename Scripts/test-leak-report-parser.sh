#!/bin/bash
# REQ-142: the leak-report parser must be shown to discriminate, not assumed to.
#
# Every failure shape COR-83 names — missing report, no count, ambiguous count, nonzero count —
# gets a fixture. A parser that silently returned 0 on a malformed report would turn the whole leak
# check into a check that always passes, which is the shape docs/DECISIONS.md exists to warn about.
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
parser="$repo_root/Scripts/leak-smoke.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

expect_count() {
    local name="$1" expected="$2" path="$3"
    local actual
    if ! actual="$("$parser" --parse-only "$path" 2>/dev/null)"; then
        echo "FAIL $name: parser rejected a valid report" >&2
        failures=$((failures + 1))
        return
    fi
    if [[ "$actual" != "$expected" ]]; then
        echo "FAIL $name: expected $expected, got $actual" >&2
        failures=$((failures + 1))
    fi
}

expect_rejection() {
    local name="$1" reason="$2" path="$3"
    local output
    if output="$("$parser" --parse-only "$path" 2>&1)"; then
        echo "FAIL $name: parser accepted a report it must reject (returned '$output')" >&2
        failures=$((failures + 1))
        return
    fi
    if [[ "$output" != *"$reason"* ]]; then
        echo "FAIL $name: rejected without the named reason '$reason': $output" >&2
        failures=$((failures + 1))
    fi
}

cat >"$work/clean.txt" <<'EOF'
leaks Report Version: 4.0, multi-line stacks
Process 100: 167110 nodes malloced for 22721 KB
Process 100: 0 leaks for 0 total leaked bytes.
EOF
expect_count "clean" 0 "$work/clean.txt"

cat >"$work/leaky.txt" <<'EOF'
leaks Report Version: 4.0, multi-line stacks
Process 100: 3 leaks for 480 total leaked bytes.
EOF
expect_count "leaky" 3 "$work/leaky.txt"

: >"$work/empty.txt"
expect_rejection "empty" "missing or empty" "$work/empty.txt"

expect_rejection "absent" "missing or empty" "$work/does-not-exist.txt"

cat >"$work/nocount.txt" <<'EOF'
leaks Report Version: 4.0, multi-line stacks
Process 100: 167110 nodes malloced for 22721 KB
error: analysis was interrupted
EOF
expect_rejection "no-count" "no leak count" "$work/nocount.txt"

cat >"$work/ambiguous.txt" <<'EOF'
Process 100: 0 leaks for 0 total leaked bytes.
Process 200: 5 leaks for 900 total leaked bytes.
EOF
expect_rejection "ambiguous" "ambiguous report" "$work/ambiguous.txt"

if (( failures > 0 )); then
    echo "test-leak-report-parser: FAILED ($failures)" >&2
    exit 1
fi
echo "test-leak-report-parser: all fixtures discriminated"
