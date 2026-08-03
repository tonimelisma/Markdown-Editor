#!/bin/bash
# COR-32: the PerformanceBoundaryTests guard.
#
# The COR-32 defect was a suite that never completed: the test host sat idle in the event loop
# with zero cases reported, and nothing failed loudly — a human had to notice the run had been
# going for hours. This script runs the suite and asserts the two properties that make a silent
# regression impossible:
#
#  1. the run finishes within a bounded wall-clock time (a hang fails loudly instead of waiting);
#  2. a nonzero number of cases actually executed (a filter that matches nothing must not pass).
#
# Test *failures* are reported but are not this gate's condition: four attribute-refresh scope
# failures belong to COR-34 and were deliberately split out of COR-32 (finding 1 of the
# investigation). COR-32 restores the suite's ability to execute; COR-34 restores its greenness,
# and Scripts/check-proof-results.sh (COR-35) then correlates every requirement row with results.
#
# It is deliberately not part of Scripts/fast-check.sh, which remains the short inner loop and
# explicitly skips this suite as "not a release gate". This guard belongs to the closing
# sequence, where the full proof set runs.
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

# The suite is ordinary patch-boundary tests and completes in seconds on a healthy host. The
# bound exists to catch "never finishes", not to time the machine; 10 minutes is generous enough
# to never trip on a slow but progressing run while still failing far sooner than a human would
# notice a hang.
timeout_seconds="${PERF_SUITE_TIMEOUT_SECONDS:-600}"
derived="${PERF_SUITE_DERIVED_DATA:-$repo_root/.perf-suite-build}"
log="$repo_root/.perf-suite.log"

start=$(date +%s)
xcodebuild test \
    -project "Markdown Editor.xcodeproj" \
    -scheme "Markdown Editor" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived" \
    -only-testing:"Markdown EditorTests/PerformanceBoundaryTests" \
    >"$log" 2>&1 &
pid=$!

# macOS has no timeout(1); poll with a bounded loop instead.
elapsed=0
while kill -0 "$pid" 2>/dev/null; do
    if (( elapsed >= timeout_seconds )); then
        echo "perf-suite: FAILED — still running after ${timeout_seconds}s (a hang, not slowness)" >&2
        # Kill only this run's test host: the derived-data path is part of the match, so a
        # developer's own running Markdown Editor app is never a target.
        pkill -9 -f "$derived.*Markdown Editor.app/Contents/MacOS" 2>/dev/null
        kill -9 "$pid" 2>/dev/null
        exit 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
done
wait "$pid"
status=$?
end=$(date +%s)

passed="$(grep -acE 'Test case .* passed' "$log")"
failed="$(grep -acE 'Test case .* failed' "$log")"
echo "perf-suite: completed in $((end - start))s — $passed passed, $failed failed"

if (( passed + failed == 0 )); then
    echo "perf-suite: FAILED — zero cases executed (filter matched nothing or the suite never started)" >&2
    exit 1
fi

if (( status != 0 && status != 65 )); then
    echo "perf-suite: FAILED — xcodebuild exited $status" >&2
    exit 1
fi

if (( failed > 0 )); then
    echo "perf-suite: suite executed; $failed failures reported (expected to be COR-34's attribute-refresh scope until that plan lands)" >&2
    grep -aE "Test case .* failed" "$log" | head -20 >&2
fi

echo "perf-suite: PASS (suite executes within the bounded wall-clock time with a nonzero case count)"
