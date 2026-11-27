#!/bin/bash
# The product screenshot gallery: one committed PNG per important screen, regenerated on demand.
#
#     Scripts/screenshots.sh              # every scene, into docs/screenshots/
#     Scripts/screenshots.sh 02-source    # one scene, by name prefix
#
# This is documentation, not a gate. `Scripts/check.sh` does not run it. It is REQ-104's
# screenshot verifier generalised: the same passive capture of the application's own window
# (never the full screen), run once per scene, with the results committed so a reader can see
# what the product looks like without building it.
#
# Nothing here drives the UI — no synthetic clicks, keystrokes, or accessibility inspection, so
# CLAUDE.md §4 still holds. A scene that an ordinary launch does not reach (Source mode, the link
# sheet) is named at launch with MARKDOWN_EDITOR_SMOKE_SCENE and applied by the application
# itself through the same window-scoped command route a toolbar click uses (REQ-151).
#
# Each run's structured diagnostics are still verified, for the reason REQ-104 gives: a
# screenshot proves what was on screen, and only the log proves the render was healthy rather
# than lucky. A scene whose log fails is reported and its PNG is not committed.
#
# Failure modes are the same three Scripts/smoke-screenshot.sh documents at length — read that
# header first if capture fails here. In short: "could not find the window" is almost never a
# permission problem, and a write failure is `screencapture`'s own file access, which is why the
# capture goes to a temp file and is copied into the repository afterwards.
#
# Environment overrides: SCREENSHOT_DERIVED_DATA, SCREENSHOT_OUT_DIR, SCREENSHOT_EXIT_SECONDS,
# SCREENSHOT_HOST_UPDATE_THRESHOLD.
#
# Not -e: the polling loops check their exit conditions explicitly.
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

out_dir="${SCREENSHOT_OUT_DIR:-$repo_root/docs/screenshots}"
derived="${SCREENSHOT_DERIVED_DATA:-$repo_root/.build/screenshots}"
exit_seconds="${SCREENSHOT_EXIT_SECONDS:-14}"
# Higher than smoke-screenshot.sh's 4: a scene applies a real mode transition (and the link scene
# a selection and a sheet presentation) after the document settles, and each of those is an
# ordinary host update. Observed counts are printed per scene below; raise this only against a
# printed number you have looked at.
host_update_threshold="${SCREENSHOT_HOST_UPDATE_THRESHOLD:-12}"

# name|fixture|scene|appearance|window height|title|caption
#
# `appearance` is passed to AppKit through the argument domain (-AppleInterfaceStyle), not read
# by application code: the product has no appearance setting of its own and must not grow one to
# be photographed.
scenes=(
    "01-wysiwyg|showcase.md|wysiwyg|light|900|Reading and writing|The rendered reading surface, with the mode switch and the formatting toolbar. Delimiters are gone; the file on disk is unchanged."
    "02-source|showcase.md|source|light|900|Source mode|The same document as literal Markdown, live-styled. This is the text that is actually on disk."
    "03-wysiwyg-dark|showcase.md|wysiwyg|dark|900|Dark appearance|The reading surface follows the system appearance, including image and code-block treatment."
    "04-link-sheet|showcase.md|link-sheet|light|900|Editing a link|Link editing is a window-attached sheet, opened over the selected link and prefilled with its destination."
    "05-markdown-coverage|smoke-rich.md|wysiwyg|light|1180|Construct coverage|Headings, inline styles, a resolved image and a labelled missing one, nested and task lists, a quote, fenced code, a table, a thematic break, and literal HTML that is shown rather than executed."
)

filter="${1:-}"

tools_dir="$(mktemp -d)"
workdir="$(mktemp -d)"
shots_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tools_dir" "$workdir" "$shots_dir"
    [[ -n "${wake_pid:-}" ]] && kill -0 "$wake_pid" 2>/dev/null && kill "$wake_pid" 2>/dev/null
    [[ -n "${app_pid:-}" ]] && kill -0 "$app_pid" 2>/dev/null && kill "$app_pid" 2>/dev/null
    return 0
}
trap cleanup EXIT

echo "screenshots: building (Debug, derivedDataPath=$derived)…"
xcodebuild -project "Markdown Editor.xcodeproj" -scheme "Markdown Editor" \
    -configuration Debug -derivedDataPath "$derived" build >"$derived.log" 2>&1 || {
        echo "screenshots: build failed; see $derived.log" >&2; tail -20 "$derived.log" >&2; exit 1; }

swiftc -O "$repo_root/Scripts/find-window-id.swift" -o "$tools_dir/find-window-id" >/dev/null || {
    echo "screenshots: failed to compile find-window-id.swift" >&2; exit 1; }

binary="$derived/Build/Products/Debug/Markdown Editor.app/Contents/MacOS/Markdown Editor"
[[ -x "$binary" ]] || { echo "screenshots: built binary not found at $binary" >&2; exit 1; }

# Autosave-in-place (REQ-005) means the launched app can write to whatever it opens, so every
# scene works on a throwaway copy of the fixture tree rather than the repository's own files.
cp -R "$repo_root/Scripts/Fixtures/." "$workdir/"

if ! command -v caffeinate >/dev/null; then
    echo "screenshots: caffeinate is unavailable; a sleeping display has no readable window surface" >&2
    exit 1
fi
caffeinate -d -i -u -t 900 &
wake_pid=$!

mkdir -p "$out_dir"

captured=0
failed=0

for row in "${scenes[@]}"; do
    IFS='|' read -r name fixture scene appearance height _title _caption <<<"$row"
    if [[ -n "$filter" && "$name" != "$filter"* ]]; then continue; fi

    logdir="$(mktemp -d)"
    shot="$shots_dir/$name.png"
    echo "── $name ($fixture, $scene, $appearance)"

    # Forcing an appearance, so the gallery does not depend on the operator's own system
    # setting. `-AppleInterfaceStyle Light` does NOT work — measured on a dark-mode machine it
    # is a no-op (mean window luma 44 versus 240 for the line below), because AppKit only tests
    # that key for the string "Dark". `NSRequiresAquaSystemAppearance` is the documented opt-out
    # and does force light. Both go through the argument domain, so neither is read by
    # application code and neither is written to the user's preferences.
    # Expanded below as ${appearance_args[@]+…}: bash 3.2 — still /bin/bash on macOS — treats an
    # empty array as unbound under `set -u`, so a future scene that forces no appearance would
    # abort the run.
    appearance_args=()
    case "$appearance" in
        dark) appearance_args=(-AppleInterfaceStyle Dark) ;;
        light) appearance_args=(-NSRequiresAquaSystemAppearance YES) ;;
    esac

    LLVM_PROFILE_FILE="$logdir/shot-%p.profraw" \
    MARKDOWN_EDITOR_DIAGNOSTICS_DIR="$logdir" \
    MARKDOWN_EDITOR_SMOKE_EXIT_SECONDS="$exit_seconds" \
    MARKDOWN_EDITOR_SMOKE_WINDOW_HEIGHT="$height" \
    MARKDOWN_EDITOR_SMOKE_SCENE="$scene" \
        "$binary" -ApplePersistenceIgnoreState YES ${appearance_args[@]+"${appearance_args[@]}"} \
        --diagnostic-smoke-exit "$workdir/$fixture" &
    app_pid=$!

    # Wait for the projection to be applied and a host update to follow it, exactly as
    # Scripts/smoke-screenshot.sh does: `availabilityChanged` alone is recorded before TextKit
    # has the projection and before the window server has composited anything.
    rendered=0
    for _ in $(seq 1 400); do
        run_file="$(find "$logdir" -name 'run-*.jsonl' -print -quit 2>/dev/null)"
        if [[ -n "$run_file" ]] && python3 - "$run_file" <<'PYEOF'
import json, sys
records = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
avail = next((r["seq"] for r in records
              if r.get("ev") == "availabilityChanged" and r.get("data", {}).get("editable") is True), None)
applied = next((r["seq"] for r in records
                if r.get("ev") == "reconciliationApplied" and r.get("doc") is not None), None)
if avail is None or applied is None:
    sys.exit(1)
sys.exit(0 if any(r.get("ev") == "hostUpdateEnded" and r["seq"] > applied for r in records) else 1)
PYEOF
        then rendered=1; break; fi
        kill -0 "$app_pid" 2>/dev/null || break
        sleep 0.05
    done
    if [[ "$rendered" -ne 1 ]]; then
        echo "screenshots: $name never rendered in time" >&2
        kill "$app_pid" 2>/dev/null; wait "$app_pid" 2>/dev/null
        rm -rf "$logdir"; failed=$((failed + 1)); continue
    fi
    # The scene is applied by the app a bounded moment after the projection lands (it needs the
    # authoritative presentation), then the window server has to composite it.
    sleep 3.0

    window_id=""
    for _ in $(seq 1 200); do
        # Matched by the exact PID launched here: a name match could select the user's own real
        # Markdown Editor window and photograph their private document.
        window_id="$("$tools_dir/find-window-id" "$app_pid" 2>/dev/null | head -1)"
        find_status=$?
        [[ "$find_status" -eq 3 ]] && break
        [[ -n "$window_id" ]] && break
        kill -0 "$app_pid" 2>/dev/null || break
        sleep 0.05
    done
    if [[ -z "$window_id" ]]; then
        if [[ "${find_status:-0}" -eq 3 ]]; then
            echo "screenshots: Screen Recording permission is MISSING (verified: windows present, no window names)." >&2
            echo "screenshots: grant it in System Settings > Privacy & Security > Screen Recording" >&2
        else
            echo "screenshots: could not find $name's window; this is NOT a permission problem." >&2
            echo "screenshots: raise SCREENSHOT_EXIT_SECONDS (currently $exit_seconds) on a slower machine." >&2
        fi
        kill "$app_pid" 2>/dev/null; wait "$app_pid" 2>/dev/null
        rm -rf "$logdir"; failed=$((failed + 1)); continue
    fi

    shot_ok=0
    for _ in $(seq 1 20); do
        rm -f "$shot"
        capture_error="$(screencapture -x -o -l"$window_id" "$shot" 2>&1 1>/dev/null)"
        capture_status=$?
        # `screencapture` can print a write failure and still exit 0, so a non-empty file is the
        # only proof it wrote one.
        if [[ "$capture_status" -eq 0 && -s "$shot" ]]; then shot_ok=1; break; fi
        kill -0 "$app_pid" 2>/dev/null || break
        sleep 0.05
    done

    # Let the application reach its own bounded self-termination rather than killing it here.
    # Killing it after the capture loses the end-of-run performance summaries the verifier below
    # requires, which reported every scene as unhealthy while the pixels were in fact fine.
    app_exit_failed=0
    for _ in $(seq 1 $(( (${exit_seconds%.*} + 12) * 10 )) ); do
        kill -0 "$app_pid" 2>/dev/null || break
        sleep 0.1
    done
    if kill -0 "$app_pid" 2>/dev/null; then
        echo "screenshots: $name did not exit in time" >&2
        kill "$app_pid" 2>/dev/null; wait "$app_pid" 2>/dev/null
        app_exit_failed=1
    else
        wait "$app_pid"
        app_exit_code=$?
        if [[ "$app_exit_code" -ne 0 ]]; then
            echo "screenshots: $name exited with status $app_exit_code" >&2
            app_exit_failed=1
        fi
    fi

    if [[ "$shot_ok" -ne 1 ]]; then
        [[ -n "${capture_error:-}" ]] && echo "screenshots: screencapture reported: $capture_error" >&2
        echo "screenshots: no image produced for $name" >&2
        rm -rf "$logdir"; failed=$((failed + 1)); continue
    fi

    # mainActorStall: `screencapture` freezes the captured process while it reads the window
    # surface, so the watchdog would report the measurement apparatus. --allow-orphaned-intents:
    # this script terminates the app at a fixed moment rather than waiting for its own bounded
    # exit, which cancels whatever the documentOpen intent still had in flight. Both allowances
    # are exactly the ones Scripts/smoke-screenshot.sh makes, for the same reasons.
    if python3 "$repo_root/Scripts/verify-smoke-log.py" \
        "$run_file" "$host_update_threshold" --label "screenshots/$name" \
        --allow-fault mainActorStall --allow-orphaned-intents \
        && [[ "$app_exit_failed" -eq 0 ]]
    then
        cp "$shot" "$out_dir/$name.png"
        echo "screenshots: wrote $out_dir/$name.png"
        captured=$((captured + 1))
    else
        echo "screenshots: $name rendered unhealthily; its image was NOT committed" >&2
        failed=$((failed + 1))
    fi
    rm -rf "$logdir"
done

if [[ -z "$filter" && "$failed" -eq 0 ]]; then
    index="$out_dir/README.md"
    {
        echo "# Screenshots"
        echo
        echo "Generated by \`Scripts/screenshots.sh\`. Do not edit by hand — regenerate instead."
        echo "Each image is one passive capture of the application's own window, taken after its"
        echo "structured diagnostics proved the render was healthy. Fixtures live in"
        echo "\`Scripts/Fixtures/\`."
        echo
        for row in "${scenes[@]}"; do
            IFS='|' read -r name fixture scene appearance height title caption <<<"$row"
            echo "## $title"
            echo
            echo "$caption"
            echo
            echo "\`$fixture\` · scene \`$scene\` · $appearance appearance · ${height}pt window"
            echo
            echo "![$name](./$name.png)"
            # No trailing blank line here: the next heading supplies its own separator and a
            # doubled blank at the end of the file fails markdownlint (MD012) in the gate.
            [[ "$row" == "${scenes[$(( ${#scenes[@]} - 1 ))]}" ]] || echo
        done
    } >"$index"
    echo "screenshots: wrote $index"
fi

echo "screenshots: $captured captured, $failed failed"
[[ "$failed" -eq 0 ]] || exit 1
