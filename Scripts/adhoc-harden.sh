#!/bin/bash
# Re-signs an ad hoc built app so it can load its own embedded frameworks, and so it is not
# published debuggable. Scripts/release.sh calls it for a build with no Developer ID; it is a
# script of its own so that the signing the release path performs can be run, and watched, by hand.
#
# An ad hoc signature carries no Team ID, and library validation — part of the hardened runtime —
# refuses any library whose team differs from the running process's. "No team" never matches "no
# team", so an ad hoc app cannot load its own embedded Sparkle.framework: build 202 was published
# and died in dyld before main, every launch ("mapping process and mapped file (non-platform) have
# different Team IDs"). Signing the bundle deeply in one pass does not help — observed both on the
# published bundle and on a build from source. The hardened runtime's library-validation exception
# does, and nothing else in the hardened runtime is given up (docs/DECISIONS.md, 2026-11-26).
#
# Only an ad hoc build needs this. With a Developer ID, every nested signature carries that team
# and library validation stays on, which is why release.sh calls this script only without one.
#
# get-task-allow goes at the same time. Xcode injects it into any non-distribution signature, so
# build 202 was published debuggable by any process of the person running it; a published app has
# no use for it, and notarisation rejects a build that carries it.
set -euo pipefail

app="${1:?the app bundle to re-sign}"
timestamp_flag="${2:---timestamp=none}"
entitlements="${3:-$(mktemp -t adhoc-entitlements)}"

refuse() {
    echo "adhoc-harden: $*" >&2
    exit 1
}

[[ -d "$app" ]] || refuse "no app bundle at $app"

/usr/bin/codesign --display --entitlements "$entitlements" --xml "$app"
# The entitlements Xcode generated from the project's capabilities, amended rather than replaced.
# If it ever stops generating them (ENABLE_USER_SELECTED_FILES), re-signing would silently take
# away the app's ability to open a file the person chose, so this stops instead.
plutil -lint "$entitlements" >/dev/null || refuse "the app's entitlements are not a plist"
/usr/libexec/PlistBuddy -c "Print :com.apple.security.files.user-selected.read-write" "$entitlements" >/dev/null 2>&1 \
    || refuse "the app's entitlements do not allow user-selected files; re-signing would drop more than it adds"
/usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$entitlements" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$entitlements" >/dev/null

/usr/bin/codesign --force --sign - --options runtime "$timestamp_flag" --entitlements "$entitlements" "$app"
echo "adhoc-harden: re-signed $app ad hoc with the library-validation exception, without get-task-allow"
