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
coverage_dir="$derived/instrumentation-coverage"
test_coverage_dir="${TMPDIR%/}/MarkdownEditorTraceCoverage"

mkdir -p "$derived"
mkdir -p "$coverage_dir"
rm -rf "$test_coverage_dir"
printf '%s\n' '── documentation authority'
./Scripts/check-documentation-authority.sh || { documentation_gate=fail; failures=$((failures + 1)); }
printf '%s\n' '── observed instrumentation coverage'
SMOKE_DERIVED_DATA="$derived/smoke" SMOKE_LOG_COPY_DIR="$coverage_dir/smoke" \
    ./Scripts/smoke-test.sh >"$coverage_dir/smoke.log" 2>&1 || {
    instrumentation_gate=fail
    tests_gate=fail
    failures=$((failures + 1))
}
printf '%s\n' '── smoke-log verifier fixtures'
./Scripts/test-verify-smoke-log.sh >/dev/null || { tests_gate=fail; failures=$((failures + 1)); }
printf '%s\n' '── push-policy fixtures'
./Scripts/test-check-push-policy.sh >/dev/null || { tests_gate=fail; failures=$((failures + 1)); }
printf '%s\n' '── complete test suite'
xcodebuild test \
    -project "Markdown Editor.xcodeproj" \
    -scheme "Markdown Editor" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived" \
    -resultBundlePath "$bundle" \
    >"$log" 2>&1
test_status=$?
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
    --log-dir "$coverage_dir/smoke" \
    --log-dir "$test_coverage_dir" || { instrumentation_gate=fail; failures=$((failures + 1)); }
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
    "$documentation_gate" "$instrumentation_gate" "$tests_gate" "$proof_gate"; then
    echo "full-check: failed to write .gate-receipt.json" >&2
    failures=$((failures + 1))
fi

if (( failures > 0 )); then
    echo "full-check: FAILED ($failures step(s))" >&2
    exit 1
fi
echo "full-check: PASS (full suite and proof floor observed; receipt scope=full)"
