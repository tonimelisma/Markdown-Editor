#!/bin/bash
# REQ-104: process-level screenshot verification. In addition to the same structured-diagnostic
# assertions Scripts/smoke-test.sh performs, this captures ONE screenshot of the application's
# own window over a richer fixture, for mandatory human/AI visual review at the end of every
# build increment. The screenshot is evidence for a human to look at — it is never itself an
# automated pass/fail assertion, and this script's own exit status depends only on structured
# diagnostic records, the same kind Scripts/smoke-test.sh checks. No UI is driven or clicked;
# this only captures a static image of a window that already rendered on its own.
#
# Captures only the application's own window (screencapture -l<windowID>), never the full
# screen: a full-screen capture would leak whatever else is currently on screen, unrelated to
# this verification and potentially sensitive.
# Not -e: the polling loops below check exit conditions explicitly rather than aborting on the
# first non-zero probe.
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

derived="${SMOKE_DERIVED_DATA:-$repo_root/.smoke-build}"
logdir="$(mktemp -d)"
tools_dir="$(mktemp -d)"
out="${SMOKE_SCREENSHOT_OUT:-$repo_root/.smoke-screenshot.png}"
cleanup() {
    rm -rf "$logdir" "$tools_dir"
    [[ -n "${app_pid:-}" ]] && kill -0 "$app_pid" 2>/dev/null && kill "$app_pid" 2>/dev/null
}
trap cleanup EXIT

echo "smoke-screenshot: building (Debug, derivedDataPath=$derived)…"
xcodebuild -project "Markdown Editor.xcodeproj" -scheme "Markdown Editor" \
    -configuration Debug -derivedDataPath "$derived" build >/dev/null || {
        echo "smoke-screenshot: build failed" >&2; exit 1; }

# Pre-compiled once: `swift find-window-id.swift` (script mode) recompiles on every invocation
# (~1.5s), too slow to poll inside the app's brief settle window. The compiled binary runs in
# well under 100ms.
swiftc -O "$repo_root/Scripts/find-window-id.swift" -o "$tools_dir/find-window-id" >/dev/null || {
    echo "smoke-screenshot: failed to compile find-window-id.swift" >&2; exit 1; }

app="$derived/Build/Products/Debug/Markdown Editor.app"
binary="$app/Contents/MacOS/Markdown Editor"
fixture="$repo_root/Scripts/Fixtures/smoke-rich.md"

if [[ ! -x "$binary" ]]; then
    echo "smoke-screenshot: built binary not found at $binary" >&2
    exit 1
fi

echo "smoke-screenshot: launching…"
MARKDOWN_EDITOR_DIAGNOSTICS_DIR="$logdir" \
    "$binary" -ApplePersistenceIgnoreState YES --diagnostic-smoke-exit "$fixture" &
app_pid=$!

run_file=""
for _ in $(seq 1 100); do
    candidate="$(find "$logdir" -name 'run-*.jsonl' -print -quit 2>/dev/null)"
    if [[ -n "$candidate" ]]; then run_file="$candidate"; break; fi
    sleep 0.05
done
if [[ -z "$run_file" ]]; then
    echo "smoke-screenshot: no run file appeared in $logdir" >&2
    exit 1
fi

# Wait for WYSIWYG to actually finish rendering before screenshotting — not just for the run
# file to appear — so the screenshot shows the fixture rendered, not an empty/half-drawn window.
rendered=0
for _ in $(seq 1 100); do
    if grep -q '"ev":"availabilityChanged".*"editable":true' "$run_file" 2>/dev/null; then
        rendered=1
        break
    fi
    sleep 0.05
done
if [[ "$rendered" -ne 1 ]]; then
    echo "smoke-screenshot: WYSIWYG never announced becoming editable in time" >&2
    exit 1
fi

window_id=""
for _ in $(seq 1 40); do
    window_id="$("$tools_dir/find-window-id" "Markdown Editor" 2>/dev/null | head -1)"
    [[ -n "$window_id" ]] && break
    sleep 0.02
done
if [[ -z "$window_id" ]]; then
    echo "smoke-screenshot: could not find the application's on-screen window" >&2
    exit 1
fi

screencapture -x -o -l"$window_id" "$out" || {
    echo "smoke-screenshot: screencapture failed — the calling process needs Screen Recording permission (System Settings > Privacy & Security > Screen Recording)" >&2
    exit 1
}
echo "smoke-screenshot: saved $out"

# Wait for the process to exit (bounded), same as smoke-test.sh.
for _ in $(seq 1 100); do
    kill -0 "$app_pid" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$app_pid" 2>/dev/null; then
    echo "smoke-screenshot: app did not exit in time" >&2
    kill "$app_pid" 2>/dev/null
    exit 1
fi
wait "$app_pid"
app_exit_code=$?
if [[ "$app_exit_code" -ne 0 ]]; then
    echo "smoke-screenshot: app exited with status $app_exit_code" >&2
    exit 1
fi

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
for previous, current in zip(seqs, seqs[1:]):
    assert current > previous, f"sequence numbers not strictly increasing: {previous} then {current}"
assert any(r["ev"] == "documentOpened" for r in records), "document never opened"
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
print(f"smoke-screenshot: diagnostics PASS ({len(records)} records, {host_updates} host updates)")
PYEOF
