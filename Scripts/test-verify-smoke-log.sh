#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
verifier="$repo_root/Scripts/verify-smoke-log.py"
fixture_dir="$repo_root/Scripts/Fixtures/SmokeLogs"

python3 "$verifier" "$fixture_dir/valid.jsonl" 20 --label valid

cases=(
    "duplicate-sequence.jsonl|strictly increasing"
    "collapsed-storm.jsonl|host did not settle"
    "two-documents.jsonl|one document handle"
    "no-reconciliation.jsonl|reconciliationApplied"
    "no-performance-samples.jsonl|no samples"
    "unknown-metric.jsonl|unknown performance metric"
    "fault.jsonl|faults recorded"
    "no-run-end.jsonl|clean-exit"
)

for item in "${cases[@]}"; do
    fixture="${item%%|*}"
    reason="${item#*|}"
    output=""
    if output="$(python3 "$verifier" "$fixture_dir/$fixture" 20 --label "$fixture" 2>&1)"; then
        echo "expected $fixture to fail" >&2
        exit 1
    fi
    if [[ "$output" != *"$reason"* ]]; then
        echo "$fixture failed without named reason '$reason': $output" >&2
        exit 1
    fi
done

echo "verify-smoke-log: all fixtures discriminated"
