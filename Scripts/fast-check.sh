#!/bin/bash
# COR-31: the short inner loop.
#
# The full `xcodebuild test` run spends most of its time in the 100,000-UTF-16 performance
# corpus, and REQ-090 already records that the latency gate must be run *focused* or it measures
# main-actor contention rather than the edit path. A quality system with a 25-minute inner loop
# gets run less often than one with a short one.
#
# A green fast check is NOT a release gate. It does not run the performance corpus and does not
# run either process-level smoke verification. The closing sequence in CLAUDE.md §3 is unchanged.
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

failures=0
documentation_gate=pass
instrumentation_gate=pass
tests_gate=pass
proof_gate=pass
step() {
    printf '\n── %s\n' "$1"
}

step "documentation authority"
./Scripts/check-documentation-authority.sh || { documentation_gate=fail; failures=$((failures + 1)); }

step "instrumentation coverage"
./Scripts/check-instrumentation-coverage.sh || { instrumentation_gate=fail; failures=$((failures + 1)); }

step "smoke-log verifier fixtures"
./Scripts/test-verify-smoke-log.sh >/dev/null || { tests_gate=fail; failures=$((failures + 1)); }

step "push-policy fixtures"
./Scripts/test-check-push-policy.sh >/dev/null || { tests_gate=fail; failures=$((failures + 1)); }

step "non-performance test suites"
# Excluded on purpose: PerformanceBoundaryTests owns the 100,000-UTF-16 corpus gates, which are
# the slow part and which REQ-090 requires be run focused rather than alongside everything else.
derived="${FAST_CHECK_DERIVED_DATA:-$repo_root/.fast-check-build}"
xcodebuild test \
    -project "Markdown Editor.xcodeproj" \
    -scheme "Markdown Editor" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived" \
    -skip-testing:"Markdown EditorTests/PerformanceBoundaryTests" \
    >"$derived.log" 2>&1
test_status=$?
if (( test_status != 0 )); then
    tests_gate=fail
    grep -aE "error:|Test case .* failed" "$derived.log" | head -20 >&2
    failures=$((failures + 1))
fi
printf 'tests: %s passed, %s failed\n' \
    "$(grep -acE 'Test case .* passed' "$derived.log")" \
    "$(grep -acE 'Test case .* failed' "$derived.log")"

step "proof results"
# The same suite excluded above is declared to the gate, so its proofs are reported as not proven
# by this run rather than counted as failures. The closing full run passes no `--skip-suite`, so
# nothing is excused there — this is the short loop being honest about what it did not measure.
FAST_CHECK_DERIVED_DATA="$derived" ./Scripts/check-proof-results.sh \
    --skip-suite PerformanceBoundaryTests || { proof_gate=fail; failures=$((failures + 1)); }

receipt_result=pass
(( failures > 0 )) && receipt_result=fail
if ! ./Scripts/write-gate-receipt.sh fast "$receipt_result" \
    "$documentation_gate" "$instrumentation_gate" "$tests_gate" "$proof_gate"; then
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
