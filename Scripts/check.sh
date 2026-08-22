#!/bin/bash
# The check. Build, test, and confirm the built app launches and renders.
#
# This replaces twelve gate scripts. If you are tempted to add a thirteenth,
# read docs/DECISIONS.md#why-the-gates-were-removed first.
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

printf '%s\n' '── build and test'
xcodebuild test \
    -project "Markdown Editor.xcodeproj" \
    -scheme "Markdown Editor" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived" \
    >"$log" 2>&1
if (( $? != 0 )); then
    failures=$((failures + 1))
    grep -aE "error:|Test case .* failed" "$log" | head -30 >&2
fi
# Indicative only. Parallel test output interleaves, so an occasional `passed` line is split
# across writes and missed here; parameterized cases each emit their own line. xcodebuild's exit
# status above is the authority on pass/fail — this number is for a sense of scale.
printf 'tests: ~%s passed, %s failed\n' \
    "$(grep -acE 'Test case .* passed' "$log" 2>/dev/null || true)" \
    "$(grep -acE 'Test case .* failed' "$log" 2>/dev/null || true)"

if (( run_smoke )); then
    printf '%s\n' '── smoke (launches the built app on a fixture)'
    if ! SMOKE_DERIVED_DATA="$derived/smoke" ./Scripts/smoke-test.sh >"$derived/smoke.log" 2>&1; then
        failures=$((failures + 1))
        tail -30 "$derived/smoke.log" >&2
    else
        echo "smoke: PASS"
    fi
fi

if (( failures > 0 )); then
    echo "check: FAILED ($failures step(s)); full log at $log" >&2
    exit 1
fi
echo "check: PASS"
