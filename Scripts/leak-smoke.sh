#!/bin/bash
# REQ-142 / COR-83: process-level leak verification.
#
# Composes Scripts/smoke-test.sh under `leaks -atExit` rather than duplicating its launch. The
# smoke run's own structured assertions still have to pass — a run with zero leaks that never
# reached `runEnd` is a crash, not a clean result.
#
# Stage 0 selected this route over xctrace; see docs/research/COR-83-leak-tooling.md.
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
derived="${CHECK_DERIVED_DATA:-$repo_root/.build/check}"
outdir="$derived/leaks"
report="$outdir/report.txt"
mkdir -p "$outdir"

# Parses a leaks report and echoes the leak count, or fails with a named reason.
# Kept as a function so Scripts/test-leak-report-parser.sh can drive it over fixtures.
parse_leak_report() {
    local path="$1"
    if [[ ! -s "$path" ]]; then
        echo "leak-smoke: report is missing or empty: $path" >&2
        return 1
    fi
    local lines
    lines="$(grep -oE '[0-9]+ leaks for [0-9]+ total leaked bytes' "$path" || true)"
    if [[ -z "$lines" ]]; then
        echo "leak-smoke: no leak count in report; the tool did not complete an analysis" >&2
        return 1
    fi
    # A report containing two different counts is ambiguous: refuse rather than pick one.
    local distinct
    distinct="$(printf '%s\n' "$lines" | sort -u | wc -l | tr -d ' ')"
    if [[ "$distinct" != "1" ]]; then
        echo "leak-smoke: ambiguous report, $distinct different leak counts:" >&2
        printf '%s\n' "$lines" | sort -u >&2
        return 1
    fi
    printf '%s\n' "$lines" | head -1 | grep -oE '^[0-9]+'
}

if [[ "${1:-}" == "--parse-only" ]]; then
    parse_leak_report "${2:?usage: leak-smoke.sh --parse-only <report>}"
    exit $?
fi

if ! command -v leaks >/dev/null 2>&1; then
    echo "leak-smoke: /usr/bin/leaks is unavailable on this system" >&2
    exit 1
fi

printf '%s\n' '── leak smoke (smoke-test.sh under leaks -atExit)'
# `leaks` stays alive analysing the process after the app exits, and smoke-test.sh's exit bound is
# measured against the launched pid — which is now `leaks`. Give that bound room for the analysis:
# SMOKE_WAIT_LOOPS overrides the derived value outright, because the derived one clamps at 700
# loops (70 s) and the analysis exceeds that on a loaded machine. Observed failing at the clamp
# immediately after a full test run. Still a bound — 3000 loops is 300 s, not "wait forever".
#
# MallocStackLogging is deliberately NOT set: it is inherited by every child process the script
# spawns (sleep, rm, bash), which floods the report the parser then has to read. Backtraces are a
# convenience for diagnosing a nonzero count, not part of the count itself; set it by hand when
# investigating one.
SMOKE_DERIVED_DATA="$derived/smoke" \
SMOKE_EXIT_SECONDS="${SMOKE_EXIT_SECONDS:-60}" \
SMOKE_WAIT_LOOPS="${SMOKE_WAIT_LOOPS:-3000}" \
SMOKE_VERIFIER_EXTRA_ARGS="--allow-fault mainActorStall" \
SMOKE_LAUNCH_WRAPPER="leaks -atExit --" \
    "$repo_root/Scripts/smoke-test.sh" >"$report" 2>&1
wrapper_status=$?

if (( wrapper_status != 0 )); then
    echo "leak-smoke: wrapped smoke run failed (exit $wrapper_status); report at $report" >&2
    tail -30 "$report" >&2
    exit 1
fi

count="$(parse_leak_report "$report")" || {
    echo "leak-smoke: report at $report" >&2
    exit 1
}

if (( count != 0 )); then
    echo "leak-smoke: $count leak(s) detected; report at $report" >&2
    grep -A 20 'leaks Report Version' "$report" | head -40 >&2
    exit 1
fi

echo "leak-smoke: PASS (0 leaks; report retained at $report)"
