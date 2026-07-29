#!/bin/bash
# REQ-098: process-level smoke verification. Launches the built application on a fixture and
# asserts only on structured diagnostic records it writes — no UI is driven, read, or asserted on.
# Not -e: the polling loops below check exit conditions explicitly rather than aborting on the
# first non-zero probe (e.g. `kill -0` on a still-running process).
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

derived="${SMOKE_DERIVED_DATA:-$repo_root/.smoke-build}"
logdir="$(mktemp -d)"
cleanup() {
    rm -rf "$logdir"
    [[ -n "${app_pid:-}" ]] && kill -0 "$app_pid" 2>/dev/null && kill "$app_pid" 2>/dev/null
}
trap cleanup EXIT

echo "smoke: building (Debug, derivedDataPath=$derived)…"
build_start=$(date +%s)
xcodebuild -project "Markdown Editor.xcodeproj" -scheme "Markdown Editor" \
    -configuration Debug -derivedDataPath "$derived" build >/dev/null || {
        echo "smoke: build failed" >&2; exit 1; }
build_end=$(date +%s)
echo "smoke: build took $((build_end - build_start))s"

app="$derived/Build/Products/Debug/Markdown Editor.app"
binary="$app/Contents/MacOS/Markdown Editor"
fixture="$repo_root/Scripts/Fixtures/smoke-basic.md"

if [[ ! -x "$binary" ]]; then
    echo "smoke: built binary not found at $binary" >&2
    exit 1
fi

echo "smoke: launching…"
launch_start=$(date +%s)
MARKDOWN_EDITOR_DIAGNOSTICS_DIR="$logdir" \
    "$binary" --diagnostic-smoke-exit "$fixture" &
app_pid=$!

# Poll for the run file rather than sleeping a fixed amount.
run_file=""
for _ in $(seq 1 100); do
    candidate="$(find "$logdir" -name 'run-*.jsonl' -print -quit 2>/dev/null)"
    if [[ -n "$candidate" ]]; then
        run_file="$candidate"
        break
    fi
    sleep 0.1
done

if [[ -z "$run_file" ]]; then
    echo "smoke: no run file appeared in $logdir" >&2
    exit 1
fi

# Wait for the process to exit (bounded) so the terminating record is durable before we read it.
for _ in $(seq 1 100); do
    kill -0 "$app_pid" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$app_pid" 2>/dev/null; then
    echo "smoke: app did not exit in time" >&2
    kill "$app_pid" 2>/dev/null
    exit 1
fi
# The process has already exited by now, so `wait` reaps it and returns its real exit status
# immediately rather than blocking — a crash during NSApp.terminate/teardown must fail the smoke
# run even if the JSON assertions below would otherwise pass on a runEnd record written earlier.
wait "$app_pid"
app_exit_code=$?
if [[ "$app_exit_code" -ne 0 ]]; then
    echo "smoke: app exited with status $app_exit_code" >&2
    exit 1
fi
launch_end=$(date +%s)
echo "smoke: launch→exit took $((launch_end - launch_start))s"

host_update_threshold="${SMOKE_HOST_UPDATE_THRESHOLD:-20}"

python3 - "$run_file" "$host_update_threshold" <<'PYEOF'
import json, sys
run_file, threshold = sys.argv[1], int(sys.argv[2])
records = [json.loads(l) for l in open(run_file) if l.strip()]
assert records, "run file is empty"
header = records[0]
assert header["v"] == 1, "unexpected schema version"
assert header["run"]["host"] == "production", f"expected production host, got {header['run'].get('host')}"
seqs = [r["seq"] for r in records[1:]]
# Strict comparison, not "seqs == sorted(seqs)": sorting a list with duplicate values leaves it
# unchanged, so that comparison would not catch a logging regression that repeats a sequence
# number, despite the header record's contract being *strictly* increasing.
for previous, current in zip(seqs, seqs[1:]):
    assert current > previous, f"sequence numbers not strictly increasing: {previous} then {current}"
assert any(r["ev"] == "documentOpened" for r in records), "document never opened"
# A storm above the log's own rate-collapse threshold stops emitting individual
# hostUpdateEnded records and reports the suppressed remainder as one "repeated" summary
# (ev == "repeated", of == "hostUpdateEnded", data.count == suppressed). Counting only direct
# records would let a real storm hide behind the collapse and pass this bounded-update check.
direct_updates = sum(1 for r in records if r["ev"] == "hostUpdateEnded")
collapsed_updates = sum(
    r.get("data", {}).get("count", 0)
    for r in records
    if r["ev"] == "repeated" and r.get("of") == "hostUpdateEnded"
)
host_updates = direct_updates + collapsed_updates
assert host_updates <= threshold, f"host did not settle: {host_updates} updates (threshold {threshold})"
faults = [r for r in records if r.get("lvl") in ("error", "fault")]
assert not faults, f"faults recorded: {[r['ev'] for r in faults]}"
assert records[-1]["ev"] == "runEnd", "no clean-exit record"
print(f"smoke: PASS ({len(records)} records, {host_updates} host updates)")
PYEOF
