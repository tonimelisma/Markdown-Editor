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
# file to appear. `availabilityChanged(editable: true)` alone is not enough: it is recorded
# synchronously when session state changes, but EditorHostView.updateNSView applies the
# projection to TextKit afterward, and the window server composites the actual pixels later
# still — screenshotting right on the availabilityChanged record risks empty, stale, or
# partially rendered pixels while every diagnostic assertion still passes. Wait for a
# hostUpdateEnded record (the host view's own update-pass signal) with a strictly later
# sequence number, then add a short fixed margin for the window server to composite.
rendered=0
for _ in $(seq 1 100); do
    if python3 - "$run_file" <<'PYEOF'
import json, sys
records = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
avail_seq = next(
    (r["seq"] for r in records
     if r.get("ev") == "availabilityChanged" and r.get("data", {}).get("editable") is True),
    None
)
if avail_seq is None:
    sys.exit(1)
has_later_host_update = any(
    r.get("ev") == "hostUpdateEnded" and r["seq"] > avail_seq for r in records
)
sys.exit(0 if has_later_host_update else 1)
PYEOF
    then
        rendered=1
        break
    fi
    sleep 0.05
done
if [[ "$rendered" -ne 1 ]]; then
    echo "smoke-screenshot: WYSIWYG never announced becoming editable (with a host update afterward) in time" >&2
    exit 1
fi
# Grace margin for the window server to actually composite the update above onto the screen;
# the diagnostic records above prove the application applied it, not that pixels are on screen.
sleep 0.2

window_id=""
for _ in $(seq 1 40); do
    # Matched by the exact PID this script launched, not by owner-name substring: if the user
    # already has their own real Markdown Editor window open, a name-only match could select
    # their document instead of the fixture, capturing unrelated (and potentially private)
    # content.
    window_id="$("$tools_dir/find-window-id" "$app_pid" 2>/dev/null | head -1)"
    [[ -n "$window_id" ]] && break
    sleep 0.02
done
if [[ -z "$window_id" ]]; then
    echo "smoke-screenshot: could not find the application's on-screen window" >&2
    echo "smoke-screenshot: if this keeps happening, check that the calling process has Screen Recording permission (System Settings > Privacy & Security > Screen Recording) — CGWindowListCopyWindowInfo returns an empty/incomplete list without it, which reads identically to \"no matching window\"" >&2
    exit 1
fi

rm -f "$out"
screencapture_err="$(screencapture -x -o -l"$window_id" "$out" 2>&1 1>/dev/null)"
screencapture_status=$?
# `screencapture` can print a write failure to stderr and still exit 0 (observed when the
# calling process lacks Screen Recording permission in some environments) — its exit code alone
# is not proof the file was written, so this checks the file landed on disk with real bytes,
# not just that the command claimed success.
if [[ -n "$screencapture_err" ]]; then
    echo "smoke-screenshot: screencapture reported: $screencapture_err" >&2
fi
if [[ "$screencapture_status" -ne 0 || ! -s "$out" ]]; then
    echo "smoke-screenshot: screencapture did not produce $out — the calling process needs Screen Recording permission (System Settings > Privacy & Security > Screen Recording)" >&2
    exit 1
fi
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
# Same rigor as smoke-test.sh: a fixture loaded more than once is a regression this script
# claims to catch (it advertises the same structured-diagnostic checks as ARC-Q12), and could
# also mean the screenshot captured an unintended document state.
loaded = [r for r in records if r["ev"] == "documentLoaded"]
assert len(loaded) == 1, f"expected exactly one documentLoaded, got {len(loaded)}"
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
