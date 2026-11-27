#!/bin/bash
# REQ-098: process-level smoke verification. Launches the built application on a fixture and
# asserts only on structured diagnostic records it writes — no UI is driven, read, or asserted on.
# Not -e: the polling loops below check exit conditions explicitly rather than aborting on the
# first non-zero probe (e.g. `kill -0` on a still-running process).
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
cleanup() {
    if [[ -n "${SMOKE_LOG_COPY_DIR:-}" && -d "$logdir" ]]; then
        mkdir -p "$SMOKE_LOG_COPY_DIR"
        cp -f "$logdir"/run-*.jsonl "$SMOKE_LOG_COPY_DIR"/ 2>/dev/null || true
    fi
    rm -rf "$logdir" "${workdir:-}"
    [[ "$cleanup_derived" -eq 1 ]] && rm -rf "$derived"
    [[ -n "${app_pid:-}" ]] && kill -0 "$app_pid" 2>/dev/null && kill "$app_pid" 2>/dev/null
}
trap cleanup EXIT

# SMOKE_APP names a bundle that already exists, to be launched as it stands instead of built.
# Scripts/release.sh sets it to the signed Release app, so the launch is a launch of exactly the
# bundle about to be published. Build 202 was published without that launch and could not start at
# all (docs/DECISIONS.md, 2026-11-26, "An ad hoc app needs the library-validation exception").
if [[ -n "${SMOKE_APP:-}" ]]; then
    app="$SMOKE_APP"
    echo "smoke: launching the given bundle, unbuilt: $app"
else
    echo "smoke: building (Debug, derivedDataPath=$derived)…"
    build_start=$(date +%s)
    source "$repo_root/Scripts/lib/build-settings.sh"
    build_command=(xcodebuild -project "Markdown Editor.xcodeproj" -scheme "Markdown Editor"
        -configuration Debug -derivedDataPath "$derived" "${verification_build_settings[@]}")
    if [[ -n "${FALSIFICATION_SOURCE_PACKAGES:-}" ]]; then
        build_command+=(-clonedSourcePackagesDirPath "$FALSIFICATION_SOURCE_PACKAGES")
    fi
    "${build_command[@]}" build >/dev/null || {
            echo "smoke: build failed" >&2; exit 1; }
    build_end=$(date +%s)
    echo "smoke: build took $((build_end - build_start))s"

    app="$derived/Build/Products/Debug/Markdown Editor.app"
fi
binary="$app/Contents/MacOS/Markdown Editor"
fixture="$repo_root/Scripts/Fixtures/smoke-basic.md"

if [[ ! -x "$binary" ]]; then
    echo "smoke: built binary not found at $binary" >&2
    exit 1
fi

echo "smoke: launching…"
launch_start=$(date +%s)
# -ApplePersistenceIgnoreState YES: a process argument, parsed into NSUserDefaults' argument
# domain, which outranks the persistent (on-disk) domain and is never written to disk. Neither
# in-process alternative is safe: UserDefaults.set(forKey:) persists to disk and would disable
# window restoration for every future ordinary launch (Debug/Release share one bundle
# identifier); UserDefaults.register(defaults:) registers into the lowest-priority domain and is
# silently overridden if the persistent domain already holds any explicit value for this key.
# An instrumented build writes its coverage profile to the working directory unless told
# otherwise, which would drop default.profraw into the repository. Redirect it into the
# temporary log directory rather than adding an ignore rule for an avoidable artifact.
# The default 2 s lifetime is enough on an idle machine but not on a loaded one: the app exits
# before the first reconciliation lands and the run then fails for "never became editable", which
# describes the machine rather than the application. 6 s costs nothing and removes the race.
# REQ-115: this run now performs real edits, and autosave-in-place (REQ-005) is enabled, so it
# must never open the repository's own fixture. Work on a throwaway copy, assets included.
workdir="$(mktemp -d)"
cp -R "$repo_root/Scripts/Fixtures/." "$workdir/"
fixture="$workdir/$(basename "$fixture")"

# The app's self-termination delay is configurable for slow machines. Wait at least that long
# plus a bounded margin before declaring a lifecycle failure; a fixed ten-second poll made the
# documented override fail by killing a healthy verifier before it could emit runEnd.
smoke_exit_seconds="${SMOKE_EXIT_SECONDS:-6}"
# SMOKE_WAIT_LOOPS overrides the derived bound outright. Needed by Scripts/leak-smoke.sh: under
# `leaks -atExit` the pid being waited on is `leaks`, which stays alive analysing the process after
# the app has exited, and that analysis can exceed the 700-loop (70 s) ceiling on a loaded machine.
# Raising SMOKE_EXIT_SECONDS cannot help, because the ceiling clamps it. This stays a bound: the
# caller states a larger one for a slower wrapper rather than the bound being removed.
smoke_wait_loops="${SMOKE_WAIT_LOOPS:-$(awk -v seconds="$smoke_exit_seconds" 'BEGIN {
    if (seconds !~ /^[0-9]+([.][0-9]+)?$/ || seconds <= 0) seconds = 2
    loops = int((seconds + 10) * 10 + 0.999)
    if (loops < 100) loops = 100
    if (loops > 700) loops = 700
    print loops
}')}"

# SMOKE_LAUNCH_WRAPPER lets a caller run the app under an analysis tool without duplicating this
# launch. Scripts/leak-smoke.sh sets it to `leaks -atExit --`; wrapping *this script* instead would
# analyse bash rather than the app, which is exactly the mistake it prevents. Unquoted on purpose:
# it is a command prefix, and empty must expand to nothing.
LLVM_PROFILE_FILE="$logdir/smoke-%p.profraw" \
MARKDOWN_EDITOR_SMOKE_EXIT_SECONDS="$smoke_exit_seconds" \
MARKDOWN_EDITOR_SMOKE_EXERCISE_EDITS=1 \
MARKDOWN_EDITOR_DIAGNOSTICS_DIR="$logdir" \
    ${SMOKE_LAUNCH_WRAPPER:-} "$binary" -ApplePersistenceIgnoreState YES --diagnostic-smoke-exit "$fixture" &
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
for _ in $(seq 1 "$smoke_wait_loops"); do
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

# REQ-096; ARC-Q11: a healthy run settles at 2 (measured, reproducibly). The previous default
# of 20 left ten-fold slack on the exact metric that exists to catch a self-feeding
# reconciliation loop, so a nine-fold regression passed silently. This run also performs two
# edits, each of which legitimately produces further host updates.
host_update_threshold="${SMOKE_HOST_UPDATE_THRESHOLD:-8}"
# SMOKE_VERIFIER_EXTRA_ARGS lets a wrapper admit a fault it provably causes, without this script
# growing knowledge of every wrapper. Scripts/leak-smoke.sh passes `--allow-fault mainActorStall`,
# because `leaks` suspends the target task to walk its memory — observed turning a 6 s run into 95 s.
# Deliberately not a general escape hatch: every value has to be a flag verify-smoke-log.py already
# defines, and each one names the fault it admits rather than disabling the check.
# shellcheck disable=SC2086
python3 "$repo_root/Scripts/verify-smoke-log.py" \
    "$run_file" "$host_update_threshold" --label smoke --expect-edits --allow-orphaned-intents \
    ${SMOKE_VERIFIER_EXTRA_ARGS:-}
