#!/bin/bash
# Proves Scripts/adhoc-harden.sh on the smallest bundle that can show the defect it repairs: an ad
# hoc app, signed with the hardened runtime, that loads a dylib from its own Contents/Frameworks.
# That is the shape v1.0.0 (build 202) shipped in and could not start (docs/DECISIONS.md,
# 2026-11-26). Built with clang here rather than taken from a build, so it runs in seconds and
# needs neither Xcode's products nor Sparkle.
#
# The control is the point: before hardening, this bundle must FAIL to launch. A hardening that
# granted nothing would pass a test that only checked the after-state.
#
# Not every host enforces library validation. GitHub's macOS runners do not — the control launches
# there, which is also why a release-time launch of the app could never have caught build 202's
# defect, and why Scripts/release.sh asserts on the entitlements rather than trusting its launch
# (docs/DECISIONS.md, 2026-11-26). Where the control launches, this says so loudly and keeps the
# assertions that do not depend on enforcement; it never reports a proof it did not make.
#
# macOS only (codesign, dyld). Scripts/check.sh runs it in the macOS section.
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0
fail() {
    echo "FAIL $*" >&2
    failures=$((failures + 1))
}

app="$work/Probe.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
cat > "$work/lib.c" <<'C'
int probe_value(void) { return 7; }
C
cat > "$work/main.c" <<'C'
#include <stdio.h>
int probe_value(void);
int main(void) { printf("probe %d\n", probe_value()); return 0; }
C
clang -dynamiclib -o "$app/Contents/Frameworks/libprobe.dylib" \
    -install_name "@rpath/libprobe.dylib" "$work/lib.c" 2>"$work/clang.log" || {
    echo "SKIP test-adhoc-harden: clang could not build the probe dylib"; sed -n 1,5p "$work/clang.log"; exit 0; }
clang -o "$app/Contents/MacOS/Probe" "$work/main.c" "$app/Contents/Frameworks/libprobe.dylib" \
    -Wl,-rpath,@executable_path/../Frameworks 2>>"$work/clang.log" || {
    echo "SKIP test-adhoc-harden: clang could not build the probe executable"; sed -n 1,5p "$work/clang.log"; exit 0; }

/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Probe" \
    -c "Add :CFBundleIdentifier string net.melisma.adhoc-probe" \
    -c "Add :CFBundlePackageType string APPL" "$app/Contents/Info.plist" >/dev/null
# The entitlements Xcode generates for this project, including the get-task-allow it injects into
# any non-distribution signature.
cat > "$work/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>com.apple.security.files.user-selected.read-write</key><true/>
    <key>com.apple.security.get-task-allow</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --options runtime --timestamp=none "$app/Contents/Frameworks/libprobe.dylib" >/dev/null 2>&1
codesign --force --sign - --options runtime --timestamp=none --entitlements "$work/entitlements.plist" "$app" >/dev/null 2>&1 \
    || fail "codesign could not sign the probe app"

run_probe() { "$app/Contents/MacOS/Probe" 2>&1; }

# Control: where library validation is enforced, it must refuse the app's own dylib.
enforced=1
before="$(run_probe)"
if [[ "$before" == "probe 7" ]]; then
    enforced=0
    echo "test-adhoc-harden: this host does not enforce library validation — the control launched."
    echo "test-adhoc-harden: csrutil: $(csrutil status 2>&1 | tr -d '\n')"
    echo "test-adhoc-harden: the launch half proves nothing here; the entitlement assertions below still run."
elif [[ "$before" != *"different Team IDs"* ]]; then
    fail "the control failed for another reason than library validation: $before"
fi

# Treatment: the script under test, and nothing else.
"$repo_root/Scripts/adhoc-harden.sh" "$app" >/dev/null || fail "adhoc-harden.sh refused the probe app"
after="$(run_probe)"
[[ "$after" == "probe 7" ]] || fail "after hardening the app still did not run: $after"
if (( enforced )) && [[ "$before" == "$after" ]]; then
    fail "hardening changed nothing on a host that enforces library validation"
fi

ent="$work/signed.plist"
codesign --display --entitlements "$ent" --xml "$app" 2>/dev/null
[[ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.cs.disable-library-validation" "$ent" 2>/dev/null)" == "true" ]] \
    || fail "the hardened app does not carry the library-validation exception"
[[ -z "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.get-task-allow" "$ent" 2>/dev/null)" ]] \
    || fail "the hardened app still carries get-task-allow"
[[ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.files.user-selected.read-write" "$ent" 2>/dev/null)" == "true" ]] \
    || fail "hardening dropped the app's own entitlements"
codesign --verify --deep --strict "$app" 2>/dev/null || fail "the hardened app's signature does not verify"

# An app whose entitlements Xcode did not generate as expected is refused rather than re-signed.
bare="$work/Bare.app"
cp -R "$app" "$bare"
: > "$work/bare.plist"
codesign --force --sign - --options runtime --timestamp=none "$bare" >/dev/null 2>&1
if "$repo_root/Scripts/adhoc-harden.sh" "$bare" >/dev/null 2>&1; then
    fail "adhoc-harden.sh re-signed an app with no entitlements instead of refusing"
fi

if (( failures )); then
    echo "test-adhoc-harden: $failures failure(s)" >&2
    exit 1
fi
if (( enforced )); then
    echo "test-adhoc-harden: PASS (control refused, hardened app ran, entitlements as intended)"
else
    echo "test-adhoc-harden: PASS (entitlements as intended) — NOT PROVED HERE: that the hardening"
    echo "test-adhoc-harden: is what makes the app loadable, because this host enforces no library validation"
fi
