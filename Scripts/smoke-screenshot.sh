#!/bin/bash
# REQ-104: process-level screenshot verification. In addition to the same structured-diagnostic
# assertions Scripts/smoke-test.sh performs, this captures ONE screenshot of the application's
# own window over a richer fixture, for mandatory human/AI visual review at the end of every
# build increment. The screenshot is evidence for a human to look at — it is never itself an
# automated assertion about appearance. The script still fails if capture itself fails or if the
# structured diagnostic proof fails. No UI is driven or clicked; this only captures a static image
# of a window that already rendered on its own.
#
# Captures only the application's own window (screencapture -l<windowID>), never the full
# screen: a full-screen capture would leak whatever else is currently on screen, unrelated to
# this verification and potentially sensitive.
# Not -e: the polling loops below check exit conditions explicitly rather than aborting on the
# first non-zero probe.
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if [[ -n "${SMOKE_DERIVED_DATA:-}" ]]; then
    derived="$SMOKE_DERIVED_DATA"
    cleanup_derived=0
else
    derived="$(mktemp -d)"
    cleanup_derived=1
fi
logdir="$(mktemp -d)"
tools_dir="$(mktemp -d)"
out="${SMOKE_SCREENSHOT_OUT:-$repo_root/.smoke-screenshot.png}"
cleanup() {
    rm -rf "$logdir" "$tools_dir"
    [[ "$cleanup_derived" -eq 1 ]] && rm -rf "$derived"
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
# An instrumented build writes its coverage profile to the working directory unless told
# otherwise, which would drop default.profraw into the repository. Redirect it into the
# temporary log directory rather than adding an ignore rule for an avoidable artifact.
LLVM_PROFILE_FILE="$logdir/smoke-%p.profraw" \
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
# partially rendered pixels while every diagnostic assertion still passes. Wait for the applied
# reconciliation and then a hostUpdateEnded record with a strictly later sequence number, then
# add a short fixed margin for the window server to composite.
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
reconciliation_seq = next(
    (r["seq"] for r in records
     if r.get("ev") == "reconciliationApplied" and r.get("doc") is not None),
    None
)
if avail_seq is None or reconciliation_seq is None:
    sys.exit(1)
has_later_host_update = any(
    r.get("ev") == "hostUpdateEnded" and r["seq"] > reconciliation_seq for r in records
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

capture_error=""
captured=0
# The window server can advertise a newly composited window just before `screencapture` can read
# its surface. Retry that bounded race while the exact launched process and window remain alive.
for _ in $(seq 1 20); do
    rm -f "$out"
    capture_error="$(screencapture -x -o -l"$window_id" "$out" 2>&1 1>/dev/null)"
    capture_status=$?
    if [[ "$capture_status" -eq 0 && -s "$out" ]]; then
        captured=1
        break
    fi
    kill -0 "$app_pid" 2>/dev/null || break
    sleep 0.05
done
# `screencapture` can print a write failure to stderr and still exit 0. Its exit code alone is not
# proof the file was written, so success requires a non-empty output file.
if [[ "$captured" -ne 1 ]]; then
    [[ -n "$capture_error" ]] && echo "smoke-screenshot: screencapture reported: $capture_error" >&2
    echo "smoke-screenshot: screencapture did not produce $out from window $window_id" >&2
    echo "smoke-screenshot: check Screen Recording permission if this is repeatable" >&2
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
python3 "$repo_root/Scripts/verify-smoke-log.py" \
    "$run_file" "$host_update_threshold" --label smoke-screenshot
