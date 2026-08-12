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
#
# ── Known failure modes, and what they actually mean ────────────────────────────────────────
#
# These were each misdiagnosed once as "missing Screen Recording permission" because that is
# what this script used to suggest for every failure. It no longer guesses: find-window-id
# exits 3 only when it has positively determined the permission is absent (windows present,
# no window names), so the messages below distinguish the real causes.
#
# 1. "could not find the application's on-screen window"
#    Usually NOT permission. The window server publishes the window *later* than the diagnostics
#    settle — measured at ~2.5 s on Apple silicon, versus the 2 s default smoke lifetime — so the
#    app terminated itself before its own window existed to capture. This script therefore runs
#    the app with MARKDOWN_EDITOR_SMOKE_EXIT_SECONDS (default 12 here) and polls for the window
#    while the process is alive. Raise SMOKE_EXIT_SECONDS on a slower machine.
#
# 2. "cannot write file to intended destination"
#    A file-access problem, not a capture problem: `screencapture` is a separate process with its
#    own file-access context and cannot always write inside the repository. The output therefore
#    defaults to a temp directory; override with SMOKE_SCREENSHOT_OUT.
#
# 3. "could not create image from window"
#    The window was found but its surface could not be read — normally the window disappearing
#    mid-capture (same root cause as 1). The capture retries while the process is alive.
#
# Environment overrides: SMOKE_DERIVED_DATA, SMOKE_SCREENSHOT_OUT, SMOKE_EXIT_SECONDS,
# SMOKE_HOST_UPDATE_THRESHOLD.
#
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
# `screencapture` runs as its own process with its own file-access context and cannot always
# write inside the repository (observed: "cannot write file to intended destination"). The
# default therefore goes to a temporary directory, which is also where a one-shot review artifact
# belongs — it is gitignored and never committed. Override with SMOKE_SCREENSHOT_OUT.
out="${SMOKE_SCREENSHOT_OUT:-$(mktemp -d)/smoke-screenshot.png}"
cleanup() {
    rm -rf "$logdir" "$tools_dir" "${workdir:-}"
    [[ "$cleanup_derived" -eq 1 ]] && rm -rf "$derived"
    [[ -n "${wake_pid:-}" ]] && kill -0 "$wake_pid" 2>/dev/null && kill "$wake_pid" 2>/dev/null
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
# Autosave-in-place (REQ-005) means a launched app can write to whatever it opens, so the
# verifier works on a throwaway copy of the fixture tree rather than the repository's own files.
workdir="$(mktemp -d)"
cp -R "$repo_root/Scripts/Fixtures/." "$workdir/"
fixture="$workdir/smoke-rich.md"

if [[ ! -x "$binary" ]]; then
    echo "smoke-screenshot: built binary not found at $binary" >&2
    exit 1
fi

# A display that is asleep still lets Core Graphics enumerate the app's window, but it has no
# readable surface for `screencapture -l<windowID>`. Ask macOS to wake the display and keep both
# display and idle sleep suppressed for this bounded verifier run. This is not UI automation and
# does not alter capture scope: the PID-specific window route below remains the only capture.
if ! command -v caffeinate >/dev/null; then
    echo "smoke-screenshot: caffeinate is unavailable; cannot establish the required display wake assertion" >&2
    exit 1
fi
caffeinate -d -i -u -t 90 &
wake_pid=$!

echo "smoke-screenshot: launching…"
# An instrumented build writes its coverage profile to the working directory unless told
# otherwise, which would drop default.profraw into the repository. Redirect it into the
# temporary log directory rather than adding an ignore rule for an avoidable artifact.
# The window server publishes the window later than the diagnostics settle (~2.5 s here, versus
# the 2 s default lifetime), so a screenshot run must outlive the log-only run or the capture
# races the application's own exit and loses.
LLVM_PROFILE_FILE="$logdir/smoke-%p.profraw" \
MARKDOWN_EDITOR_DIAGNOSTICS_DIR="$logdir" \
MARKDOWN_EDITOR_SMOKE_EXIT_SECONDS="${SMOKE_EXIT_SECONDS:-12}" \
MARKDOWN_EDITOR_SMOKE_WINDOW_HEIGHT="${SMOKE_WINDOW_HEIGHT:-980}" \
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
# Bounded by the launched process staying alive rather than by a fixed count: the window can be
# published a second or more after the diagnostics say the projection was applied.
for _ in $(seq 1 200); do
    # Matched by the exact PID this script launched, not by owner-name substring: if the user
    # already has their own real Markdown Editor window open, a name-only match could select
    # their document instead of the fixture, capturing unrelated (and potentially private)
    # content.
    window_id="$("$tools_dir/find-window-id" "$app_pid" 2>/dev/null | head -1)"
    find_status=$?
    # Exit 3 means the finder positively determined the permission is missing. Anything else is
    # simply "not up yet", so keep polling while the process lives.
    [[ "$find_status" -eq 3 ]] && break
    [[ -n "$window_id" ]] && break
    kill -0 "$app_pid" 2>/dev/null || break
    sleep 0.05
done
if [[ -z "$window_id" ]]; then
    if [[ "${find_status:-0}" -eq 3 ]]; then
        echo "smoke-screenshot: Screen Recording permission is MISSING for this process." >&2
        echo "smoke-screenshot: grant it in System Settings > Privacy & Security > Screen Recording" >&2
        echo "smoke-screenshot: (verified, not guessed: the window list returned windows but no window names)" >&2
    else
        echo "smoke-screenshot: could not find the application's on-screen window." >&2
        echo "smoke-screenshot: Screen Recording permission is present — this is NOT a permission problem." >&2
        echo "smoke-screenshot: the window is published later than the diagnostics settle; if the app" >&2
        echo "smoke-screenshot: exited first, raise SMOKE_EXIT_SECONDS (currently ${SMOKE_EXIT_SECONDS:-12})." >&2
    fi
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
    echo "smoke-screenshot: the window was found, so Screen Recording permission is present." >&2
    echo "smoke-screenshot: 'cannot write file to intended destination' is a file-access problem —" >&2
    echo "smoke-screenshot: set SMOKE_SCREENSHOT_OUT to a path screencapture can write." >&2
    capture_failed=1
else
    echo "smoke-screenshot: saved $out"
    capture_failed=0
fi

# Wait for the process to exit (bounded), same as smoke-test.sh. Keep this result separate from
# capture and diagnostics so a timeout or nonzero application exit cannot be hidden by a later
# successful screenshot or by the verifier's own exit status.
app_exit_failed=0
app_exit_code=0
for _ in $(seq 1 100); do
    kill -0 "$app_pid" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$app_pid" 2>/dev/null; then
    echo "smoke-screenshot: APPLICATION EXIT FAILED (app did not exit in time)" >&2
    app_exit_failed=1
    kill "$app_pid" 2>/dev/null
    wait "$app_pid" 2>/dev/null || true
    app_exit_code=124
else
    wait "$app_pid"
    app_exit_code=$?
fi
if [[ "$app_exit_code" -ne 0 ]]; then
    if [[ "$app_exit_failed" -eq 0 ]]; then
        echo "smoke-screenshot: APPLICATION EXIT FAILED (app exited with status $app_exit_code)" >&2
    fi
    app_exit_failed=1
fi

# The application's own diagnostics are verified even when capture failed: a missing Screen
# Recording permission is an environment fault and must not be reported as, or hide, an
# application fault. The two outcomes are reported separately and the script fails if either did.
# REQ-096; ARC-Q11: measured-healthy is 2. This run performs no edits, so its ceiling is
# tighter than smoke-test.sh's.
host_update_threshold="${SMOKE_HOST_UPDATE_THRESHOLD:-4}"
# mainActorStall is tolerated here and only here: `screencapture` freezes the captured process
# while it reads the window surface, so the watchdog reports the measurement apparatus rather
# than the application. Scripts/smoke-test.sh runs the same app with no capture and tolerates
# nothing, so a real stall still fails a gate.
python3 "$repo_root/Scripts/verify-smoke-log.py" \
    "$run_file" "$host_update_threshold" --label smoke-screenshot --allow-fault mainActorStall
diagnostics_status=$?

if [[ "$capture_failed" -eq 1 ]]; then
    echo "smoke-screenshot: CAPTURE FAILED (environment); visual review evidence was not produced" >&2
    exit 1
fi
if [[ "$app_exit_failed" -eq 1 ]]; then
    echo "smoke-screenshot: application did not have a clean exit" >&2
    exit 1
fi
exit "$diagnostics_status"
