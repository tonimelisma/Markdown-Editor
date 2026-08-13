#!/bin/bash
# COR-31: the short inner loop.
#
# The full `xcodebuild test` run spends most of its time in the 100,000-UTF-16 performance
# corpus, and REQ-090 already records that the latency gate must be run *focused* or it measures
# main-actor contention rather than the edit path. A quality system with a 25-minute inner loop
# gets run less often than one with a short one.
#
# A green fast check is NOT a release gate. It does not run the performance corpus. COR-58 adds a
# bounded process smoke run because observed trace coverage cannot be established from source text.
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

failures=0
documentation_gate=pass
instrumentation_gate=pass
tests_gate=pass
proof_gate=pass
delivery_gate=pass
falsification_gate=pass
derived="${FAST_CHECK_DERIVED_DATA:-$repo_root/.fast-check-build}"
coverage_dir="$derived/instrumentation-coverage"
# Isolate trace coverage per checkout so concurrent worktree gate runs cannot
# read each other's diagnostic output. Previous value was a single shared
# ${TMPDIR%/}/MarkdownEditorTraceCoverage. Now per-checkout via FNV-1a hash of
# repo_root (matching Markdown EditorTests/DiagnosticLogTests.swift fallback) and
# overrideable via EDITOR_TRACE_COVERAGE_LOG_DIR (same pattern as
# FAST_CHECK_DERIVED_DATA / FULL_CHECK_DERIVED_DATA). The hash is computed both
# in Swift (#filePath) and here, so no environment propagation is required for
# xcodebuild test hosts.
if [[ -n "${EDITOR_TRACE_COVERAGE_LOG_DIR:-}" ]]; then
    test_coverage_dir="$EDITOR_TRACE_COVERAGE_LOG_DIR"
else
    test_coverage_dir="$repo_root/.build/instrumentation-coverage-tests"
fi
mkdir -p "$coverage_dir"
mkdir -p "$test_coverage_dir"
rm -rf "$test_coverage_dir"/*
touch "$test_coverage_dir/.enabled"
export EDITOR_TRACE_COVERAGE_LOG_DIR="$test_coverage_dir"
start_coverage_capture() {
    local pipe_path="$1"
    local output_path="$2"
    mkdir -p "$(dirname "$output_path")"
    rm -f "$pipe_path" "$output_path"
    mkfifo "$pipe_path"
    cat "$pipe_path" > "$output_path" &
    coverage_reader_pid=$!
    export EDITOR_TRACE_COVERAGE_LOG_DIR="$(dirname "$pipe_path")"
}
stop_coverage_capture() {
    kill "$coverage_reader_pid" 2>/dev/null || true
    wait "$coverage_reader_pid" 2>/dev/null || true
    rm -f "$EDITOR_TRACE_COVERAGE_LOG_DIR/route.pipe"
}
step() {
    printf '\n── %s\n' "$1"
}

step "documentation authority"
./Scripts/check-documentation-authority.sh || { documentation_gate=fail; failures=$((failures + 1)); }

step "measurement provenance"
./Scripts/check-measurement-provenance.sh || { failures=$((failures + 1)); }
./Scripts/test-check-measurement-provenance.sh || { failures=$((failures + 1)); }

step "observed instrumentation coverage"
start_coverage_capture "$test_coverage_dir/route.pipe" "$coverage_dir/smoke/production-route.jsonl"
SMOKE_DERIVED_DATA="$derived/smoke" SMOKE_LOG_COPY_DIR="$coverage_dir/smoke" \
    ./Scripts/smoke-test.sh >"$coverage_dir/smoke.log" 2>&1 || {
    instrumentation_gate=fail
    tests_gate=fail
    failures=$((failures + 1))
}
stop_coverage_capture

step "smoke-log verifier fixtures"
./Scripts/test-verify-smoke-log.sh >/dev/null || { tests_gate=fail; failures=$((failures + 1)); }

step "push-policy fixtures"
./Scripts/test-check-push-policy.sh >/dev/null || { tests_gate=fail; failures=$((failures + 1)); }
./Scripts/test-check-delivery-status.sh >/dev/null || { tests_gate=fail; failures=$((failures + 1)); }

step "changed-scope falsification"
export FALSIFICATION_SOURCE_PACKAGES="${FALSIFICATION_SOURCE_PACKAGES:-$derived/smoke/SourcePackages}"
if [[ -n "${FALSIFICATION_BASE:-}" ]]; then
    falsification_base="$FALSIFICATION_BASE"
elif git rev-parse --verify origin/main >/dev/null 2>&1; then
    falsification_base="$(git merge-base origin/main HEAD)"
else
    echo "fast-check: cannot determine falsification base; origin/main is missing" >&2
    falsification_gate=fail
    failures=$((failures + 1))
    falsification_base=""
fi
if [[ -n "$falsification_base" ]]; then
./Scripts/check-falsification.sh --changed "$falsification_base..HEAD" || {
    falsification_gate=fail
    failures=$((failures + 1))
}
fi

step "non-performance test suites"
# Excluded on purpose: PerformanceBoundaryTests owns the 100,000-UTF-16 corpus gates, which are
# the slow part and which REQ-090 requires be run focused rather than alongside everything else.
start_coverage_capture "$test_coverage_dir/route.pipe" "$test_coverage_dir/production-route.jsonl"
xcodebuild test \
    -project "Markdown Editor.xcodeproj" \
    -scheme "Markdown Editor" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived" \
    -skip-testing:"Markdown EditorTests/PerformanceBoundaryTests" \
    >"$derived.log" 2>&1
test_status=$?
stop_coverage_capture
if (( test_status != 0 )); then
    tests_gate=fail
    grep -aE "error:|Test case .* failed" "$derived.log" | head -20 >&2
    failures=$((failures + 1))
fi
printf 'tests: %s passed, %s failed\n' \
    "$(grep -acE 'Test case .* passed' "$derived.log")" \
    "$(grep -acE 'Test case .* failed' "$derived.log")"

step "observed instrumentation coverage gate"
./Scripts/check-instrumentation-coverage.sh \
    --log-dir "$coverage_dir/smoke/production-route.jsonl" \
    --log-dir "$test_coverage_dir/production-route.jsonl" || { instrumentation_gate=fail; failures=$((failures + 1)); }
./Scripts/test-check-instrumentation-coverage.sh || { instrumentation_gate=fail; failures=$((failures + 1)); }

step "proof results"
# The same suite excluded above is declared to the gate, so its proofs are reported as not proven
# by this run rather than counted as failures. The closing full run passes no `--skip-suite`, so
# nothing is excused there — this is the short loop being honest about what it did not measure.
FAST_CHECK_DERIVED_DATA="$derived" ./Scripts/check-proof-results.sh \
    --skip-suite PerformanceBoundaryTests || { proof_gate=fail; failures=$((failures + 1)); }

delivery_gate=structural
./Scripts/check-delivery-status.sh --structural-only || { delivery_gate=fail; failures=$((failures + 1)); }

receipt_result=pass
(( failures > 0 )) && receipt_result=fail
if ! ./Scripts/write-gate-receipt.sh fast "$receipt_result" \
    "$documentation_gate" "$instrumentation_gate" "$tests_gate" "$proof_gate" "$delivery_gate" "$falsification_gate"; then
    echo "fast-check: failed to write .gate-receipt.json" >&2
    failures=$((failures + 1))
fi

if (( failures > 0 )); then
    printf '\nfast-check: FAILED (%d step%s)\n' \
        "$failures" "$([[ $failures -eq 1 ]] && printf '' || printf 's')" >&2
    printf 'fast-check: this is the short loop; a failure here is real, but a pass is not a release gate.\n' >&2
    exit 1
fi

printf '\nfast-check: PASS (not a release gate — run the full suite, both smoke scripts, and the Release performance proof before merging)\n'
