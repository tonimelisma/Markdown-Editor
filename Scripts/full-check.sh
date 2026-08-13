#!/bin/bash
# COR-57: the complete local release gate and full-scope receipt producer.
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
derived="${FULL_CHECK_DERIVED_DATA:-$repo_root/.full-check-build}"
bundle="${FULL_CHECK_RESULT_BUNDLE:-$derived/Full.xcresult}"
log="${FULL_CHECK_LOG:-$derived.log}"
failures=0
documentation_gate=pass
instrumentation_gate=pass
tests_gate=pass
proof_gate=pass
delivery_gate=pass
falsification_gate=pass
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
coverage_pipe_dir="$repo_root/.build/instrumentation-coverage-tests"
mkdir -p "$derived"
mkdir -p "$coverage_dir"
mkdir -p "$test_coverage_dir"
mkdir -p "$coverage_pipe_dir"
rm -rf "$test_coverage_dir"/*
touch "$test_coverage_dir/.enabled"
export EDITOR_TRACE_COVERAGE_LOG_DIR="$test_coverage_dir"
coverage_pipe_path=""
coverage_session=""
start_coverage_capture() {
    local pipe_path="$1"
    local output_path="$2"
    mkdir -p "$(dirname "$output_path")"
    rm -f "$pipe_path" "$output_path"
    mkfifo "$pipe_path"
    cat "$pipe_path" > "$output_path" &
    coverage_reader_pid=$!
    coverage_pipe_path="$pipe_path"
    coverage_session="$(openssl rand -hex 16)"
    printf '%s\n' "$coverage_session" > "$(dirname "$output_path")/.coverage-session"
    export EDITOR_TRACE_COVERAGE_SESSION="$coverage_session"
}
stop_coverage_capture() {
    kill "$coverage_reader_pid" 2>/dev/null || true
    wait "$coverage_reader_pid" 2>/dev/null || true
    rm -f "$coverage_pipe_path"
}
printf '%s\n' '── documentation authority'
./Scripts/check-documentation-authority.sh || { documentation_gate=fail; failures=$((failures + 1)); }
printf '%s\n' '── measurement provenance'
./Scripts/check-measurement-provenance.sh || { failures=$((failures + 1)); }
./Scripts/test-check-measurement-provenance.sh || { failures=$((failures + 1)); }
printf '%s\n' '── observed instrumentation coverage'
start_coverage_capture "$coverage_pipe_dir/route.pipe" "$coverage_dir/smoke/production-route.jsonl"
SMOKE_DERIVED_DATA="$derived/smoke" SMOKE_LOG_COPY_DIR="$coverage_dir/smoke" \
    ./Scripts/smoke-test.sh >"$coverage_dir/smoke.log" 2>&1 || {
    instrumentation_gate=fail
    tests_gate=fail
    failures=$((failures + 1))
}
stop_coverage_capture
printf '%s\n' '── smoke-log verifier fixtures'
./Scripts/test-verify-smoke-log.sh >/dev/null || { tests_gate=fail; failures=$((failures + 1)); }
printf '%s\n' '── push-policy fixtures'
./Scripts/test-check-push-policy.sh >/dev/null || { tests_gate=fail; failures=$((failures + 1)); }
./Scripts/test-check-delivery-status.sh >/dev/null || { tests_gate=fail; failures=$((failures + 1)); }
printf '%s\n' '── changed-scope falsification'
export FALSIFICATION_SOURCE_PACKAGES="${FALSIFICATION_SOURCE_PACKAGES:-$derived/smoke/SourcePackages}"
if [[ -n "${FALSIFICATION_BASE:-}" ]]; then
    falsification_base="$FALSIFICATION_BASE"
elif git rev-parse --verify origin/main >/dev/null 2>&1; then
    falsification_base="$(git merge-base origin/main HEAD)"
else
    echo "full-check: cannot determine falsification base; origin/main is missing" >&2
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
printf '%s\n' '── complete test suite'
# xcodebuild refuses to overwrite an existing result bundle, so leaving the previous run's
# bundle in place made every full-check after the first exit before running a single test —
# reporting "0 passed, 0 failed" and taking the observed-coverage gate down with it, because
# no run had emitted anything. The proof-results gate reads this bundle, so it must be the
# product of this run and no other.
rm -rf "$bundle"
start_coverage_capture "$coverage_pipe_dir/route.pipe" "$test_coverage_dir/production-route.jsonl"
xcodebuild test \
    -project "Markdown Editor.xcodeproj" \
    -scheme "Markdown Editor" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived" \
    -resultBundlePath "$bundle" \
    >"$log" 2>&1
test_status=$?
stop_coverage_capture
if (( test_status != 0 )); then
    tests_gate=fail
    failures=$((failures + 1))
    grep -aE "error:|Test case .* failed" "$log" | head -20 >&2
fi
printf 'tests: %s passed, %s failed\n' \
    "$(grep -acE 'Test case .* passed' "$log" 2>/dev/null || true)" \
    "$(grep -acE 'Test case .* failed' "$log" 2>/dev/null || true)"
printf '%s\n' '── observed instrumentation coverage gate'
./Scripts/check-instrumentation-coverage.sh \
    --log-dir "$coverage_dir/smoke/production-route.jsonl" \
    --log-dir "$test_coverage_dir/production-route.jsonl" \
    --session-file "$coverage_dir/smoke/.coverage-session" \
    --session-file "$test_coverage_dir/.coverage-session" || { instrumentation_gate=fail; failures=$((failures + 1)); }
./Scripts/test-check-instrumentation-coverage.sh || { instrumentation_gate=fail; failures=$((failures + 1)); }
printf '%s\n' '── proof results'
if ! ./Scripts/check-proof-results.sh "$bundle"; then
    proof_gate=fail
    failures=$((failures + 1))
fi
printf '%s\n' '── derived delivery status'
if ! ./Scripts/check-delivery-status.sh "$bundle"; then
    delivery_gate=fail
    failures=$((failures + 1))
fi

receipt_result=pass
(( failures > 0 )) && receipt_result=fail
if ! ./Scripts/write-gate-receipt.sh full "$receipt_result" \
    "$documentation_gate" "$instrumentation_gate" "$tests_gate" "$proof_gate" "$delivery_gate" "$falsification_gate"; then
    echo "full-check: failed to write .gate-receipt.json" >&2
    failures=$((failures + 1))
fi

if (( failures > 0 )); then
    echo "full-check: FAILED ($failures step(s))" >&2
    exit 1
fi
echo "full-check: PASS (full suite and proof floor observed; receipt scope=full)"
