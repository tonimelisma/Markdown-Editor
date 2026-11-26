#!/bin/bash
# The check. Build, test, and confirm the built app launches and renders.
#
# This replaces twelve gate scripts. If you are tempted to add a thirteenth,
# read docs/DECISIONS.md#why-the-gates-were-removed first.
#
# On a Mac with Xcode it runs everything. Anywhere else (a Claude Code cloud session, an Ubuntu CI
# job) it runs only the steps that need no Xcode and ends `check: INCOMPLETE` with exit status 3:
# the build, the tests and the smoke run are then CI's macOS job, and nothing has verified them
# yet. Exit 3 is deliberately not 0 — a check that silently skipped the build would be the
# "filtered run that matches nothing reports success" trap CLAUDE.md §3 describes.
#
# Exit status: 0 PASS · 1 FAILED · 2 usage · 3 INCOMPLETE (portable steps passed; no Xcode here).
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
derived="${CHECK_DERIVED_DATA:-$repo_root/.build/check}"
log="${CHECK_LOG:-$derived.log}"
failures=0

run_smoke=1
for arg in "$@"; do
    case "$arg" in
        --no-smoke) run_smoke=0 ;;
        --help)
            echo "usage: check.sh [--no-smoke]"
            exit 0
            ;;
        *)
            echo "check: unknown argument $arg" >&2
            exit 2
            ;;
    esac
done

mkdir -p "$derived"
source "$repo_root/Scripts/lib/build-settings.sh"
started_at=$(date +%s)

has_xcode=0
if [[ "$(uname -s)" == Darwin ]] && xcodebuild -version >/dev/null 2>&1; then
    has_xcode=1
fi

# The release scripts' pure parts (version, feed). Portable; runs everywhere.
printf '%s\n' '── release scripts'
if ! ./Scripts/test-release-scripts.sh >"$derived/release-scripts.log" 2>&1; then
    failures=$((failures + 1))
    tail -20 "$derived/release-scripts.log" >&2
else
    echo "release scripts: PASS"
fi

if (( has_xcode )); then
    printf '%s\n' '── build and test'
    results="$derived/tests.xcresult"
    rm -rf "$results"
    xcodebuild test \
        -resultBundlePath "$results" \
        -project "Markdown Editor.xcodeproj" \
        -scheme "Markdown Editor" \
        -configuration Debug \
        -destination 'platform=macOS' \
        -derivedDataPath "$derived" \
        "${verification_build_settings[@]}" \
        >"$log" 2>&1
    if (( $? != 0 )); then
        failures=$((failures + 1))
        grep -aE "error:|Test case .* failed" "$log" | head -30 >&2
        # xcodebuild's console never prints a Swift Testing issue's text, which is the part that
        # says what failed. Read it from the result bundle, so a cloud session sees it in CI's log.
        if [[ -d "$results" ]]; then
            xcrun xcresulttool get test-results tests --path "$results" --format json 2>/dev/null \
                | python3 -I -c '
import json, sys
def walk(node, path):
    name = node.get("name", "")
    if node.get("nodeType") == "Failure Message":
        print("failure: %s: %s" % (path, name))
    for child in node.get("children", []):
        walk(child, name if node.get("nodeType") == "Test Case" else path)
for root in json.load(sys.stdin).get("testNodes", []):
    walk(root, "")
' >&2 || echo "check: could not read failure messages from $results" >&2
        fi
    fi
    # Indicative only. Parallel test output interleaves, so an occasional `passed` line is split
    # across writes and missed here; parameterized cases each emit their own line. xcodebuild's exit
    # status above is the authority on pass/fail — this number is for a sense of scale.
    warnings="$(grep -acE 'warning:' "$log" 2>/dev/null || true)"
    if (( warnings > 0 )); then
        # Incremental: already-compiled files emit nothing, so this undercounts. It is a drift
        # signal, not a census — run a clean build when it moves.
        printf 'warnings: %s (incremental build; run a clean build for a full count)\n' "$warnings"
    fi
    printf 'tests: ~%s passed, %s failed\n' \
        "$(grep -acE 'Test case .* passed' "$log" 2>/dev/null || true)" \
        "$(grep -acE 'Test case .* failed' "$log" 2>/dev/null || true)"
fi

if (( run_smoke )); then
    # The smoke verifier is REQ-098's proof, so it has to be shown to still discriminate: these
    # fixtures are nine deliberately broken logs it must reject. Without this, a verifier that
    # silently stopped checking would let every smoke run pass vacuously. Cheap — pure Python.
    printf '%s\n' '── report-parser fixtures'
    if ! ./Scripts/test-leak-report-parser.sh >"$derived/leak-parser-fixtures.log" 2>&1; then
        failures=$((failures + 1))
        tail -20 "$derived/leak-parser-fixtures.log" >&2
    else
        echo "leak-report parser: PASS"
    fi

    printf '%s\n' '── smoke-verifier fixtures'
    if ! ./Scripts/test-verify-smoke-log.sh >"$derived/verifier-fixtures.log" 2>&1; then
        failures=$((failures + 1))
        tail -20 "$derived/verifier-fixtures.log" >&2
    else
        echo "verifier fixtures: PASS"
    fi

    printf '%s\n' '── docs'
    if command -v npx >/dev/null 2>&1; then
        if ! npx --yes markdownlint-cli2 >"$derived/markdownlint.log" 2>&1; then
            failures=$((failures + 1))
            tail -20 "$derived/markdownlint.log" >&2
        else
            echo "markdownlint: PASS"
        fi
    else
        echo "markdownlint: SKIPPED (no npx)"
    fi

    if (( has_xcode )); then
        # The Debug app the smoke run launches is signed without the hardened runtime
        # (ENABLE_DEBUG_DYLIB), so no launch here exercises how a release is signed — which is how
        # build 202 was published unable to start (docs/DECISIONS.md, 2026-11-26). This proves the
        # script that repairs it, on a bundle built for the purpose: seconds, and its control must
        # fail to launch before it passes.
        printf '%s\n' '── ad hoc hardening (the release signing a Debug launch cannot show)'
        if ! ./Scripts/test-adhoc-harden.sh >"$derived/adhoc-harden.log" 2>&1; then
            failures=$((failures + 1))
            tail -20 "$derived/adhoc-harden.log" >&2
        else
            echo "ad hoc hardening: PASS"
        fi

        printf '%s\n' '── smoke (launches the built app on a fixture)'
        # The run's own diagnostics (JSON Lines) are kept beside the log, so a failed smoke run says
        # what it recorded (a stall's duration and moment), not only that it failed.
        rm -rf "$derived/smoke-records"
        if ! SMOKE_DERIVED_DATA="$derived/smoke" SMOKE_LOG_COPY_DIR="$derived/smoke-records" \
            ./Scripts/smoke-test.sh >"$derived/smoke.log" 2>&1; then
            failures=$((failures + 1))
            tail -30 "$derived/smoke.log" >&2
        else
            echo "smoke: PASS"
        fi
    fi
fi

# The five-minute budget (docs/DECISIONS.md, 2026-11-26) counts this run plus CI's. Printed so
# a run's cost is read against it, not guessed.
duration=$(( $(date +%s) - started_at ))
printf 'duration: %dm%02ds (budget: 5m for a commit, local and CI together)\n' $((duration / 60)) $((duration % 60))

if (( failures > 0 )); then
    echo "check: FAILED ($failures step(s)); full log at $log" >&2
    exit 1
fi
if (( ! has_xcode )); then
    echo "check: INCOMPLETE — portable steps passed; build, tests and smoke need macOS and run in CI's macOS job"
    exit 3
fi
echo "check: PASS"
