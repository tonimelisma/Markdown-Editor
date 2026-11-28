#!/bin/bash
# Builds, signs and publishes the checked-out main commit as an update (ADR 0010). `.github/workflows/release.yml` runs it on GitHub's macOS runner
# once that commit's CI passed; it publishes to GitHub, so it is not run by hand.
#
# A release is made only when the published app changed since the newest release (anything under
# `Markdown Editor/` or `Markdown Editor.xcodeproj/`, or in the scripts that sign it). It is
# v<x.y.z>, the next version of the
# project's MARKETING_VERSION series (Scripts/release-version.sh), with CFBundleVersion the commit
# count, the number Sparkle compares. It holds the disk image a person installs from
# (Markdown-Editor.dmg), the Sparkle archive, and the feed that names it (Scripts/appcast.sh). It is
# refused while the pinned Sparkle has known advisories (Scripts/sparkle-advisories.sh). It is
# marked latest, so releases/latest/download/appcast.xml always names the newest build. Only the
# newest three releases are kept.
#
# Nothing here needs a Mac of anyone's (ADR 0011).
#
# The environment the workflow gives it:
#   SPARKLE_SEED         the secret the update key is derived from (Scripts/sparkle-key.sh); its
#                        public half is stamped into the build as SUPublicEDKey
#   OPENSSL              an OpenSSL 3 binary for Scripts/sparkle-key.sh
#   GH_TOKEN, GITHUB_REPOSITORY
#
# The app is signed ad hoc and is not notarized: there is no Apple Developer account and there will
# not be one (ADR 0015). Sparkle checks the update's EdDSA signature, not its
# signing identity, so updates do not need one.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

: "${SPARKLE_SEED:?the seed of the update key is needed}"
: "${GITHUB_REPOSITORY:?the repository is needed}"
publish_repo="$GITHUB_REPOSITORY"
keep=3
project="Markdown Editor.xcodeproj"
# app_paths: what makes the published app differ from the newest release (Scripts/lib/app-paths.sh).
source "$(dirname "$0")/lib/app-paths.sh"

say() { echo "release: $*"; }
refuse() {
    echo "release: $*" >&2
    exit 1
}

[[ -z "$(git status --porcelain)" ]] || refuse "the checkout is dirty"
sha="$(git rev-parse HEAD)"
build="$(git rev-list --count HEAD)"

# The newest release, and whether this commit changes the app it holds, by the `source-commit:
# <sha>` line each release's notes end with. The workflow runs one release at a time.
latest="$(gh release list --repo "$publish_repo" --limit 100 --json tagName,isLatest --jq '.[] | select(.isLatest) | .tagName')"
if [[ -n "$latest" ]]; then
    released="$(gh release view "$latest" --repo "$publish_repo" --json body --jq .body | sed -n 's/^source-commit: \([0-9a-f]\{40\}\)$/\1/p' | tail -1)"
    if [[ -n "$released" ]] && git cat-file -e "$released^{commit}" 2>/dev/null; then
        if git merge-base --is-ancestor "$sha" "$released"; then
            say "skipped: $sha is not newer than $latest"
            exit 0
        fi
        if git diff --quiet "$released" "$sha" -- "${app_paths[@]}"; then
            say "skipped: the app is unchanged since $latest"
            exit 0
        fi
    fi
fi

# The version: the next of the MARKETING_VERSION series after the newest v<x.y.z>.
series="$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' "$project/project.pbxproj" | sort -u)"
[[ "$(printf '%s\n' "$series" | grep -c .)" == 1 ]] || refuse "the targets' MARKETING_VERSIONs differ: $(printf '%s' "$series" | tr '\n' ' ')"
newest="$(gh release list --repo "$publish_repo" --limit 100 --json tagName --jq '.[].tagName' \
    | sed -n 's/^v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$/\1/p' | sort -V | tail -1)"
version="$(./Scripts/release-version.sh "$series" "$newest")"
tag="v$version"

./Scripts/sparkle-advisories.sh

public_key="$(./Scripts/sparkle-key.sh public)"
say "signing: ad hoc; update key $public_key"

derived="$repo_root/build/ReleaseDerivedData"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

xcodebuild \
    -project "$project" \
    -scheme "Markdown Editor" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    PROVISIONING_PROFILE_SPECIFIER= \
    OTHER_CODE_SIGN_FLAGS=--timestamp=none \
    SPARKLE_PUBLIC_ED_KEY="$public_key" \
    CURRENT_PROJECT_VERSION="$build" \
    MARKETING_VERSION="$version" \
    build

app="$derived/Build/Products/Release/Markdown Editor.app"
plist="$app/Contents/Info.plist"

# An ad hoc build cannot load its own embedded Sparkle.framework under library validation — build
# 202 was published and could not start at all. Scripts/adhoc-harden.sh says why, and re-signs it
# with the exception and without get-task-allow.
./Scripts/adhoc-harden.sh "$app" --timestamp=none "$out/adhoc.entitlements"

/usr/bin/codesign --verify --deep --strict "$app"

# What the app is actually signed with, read back off the bundle rather than assumed.
signed_entitlements="$out/signed.entitlements"
/usr/bin/codesign --display --entitlements "$signed_entitlements" --xml "$app"
entitled() { /usr/libexec/PlistBuddy -c "Print :$1" "$signed_entitlements" 2>/dev/null || true; }
[[ "$(entitled com.apple.security.cs.disable-library-validation)" == "true" ]] \
    || refuse "the ad hoc app does not carry com.apple.security.cs.disable-library-validation, so it cannot load Sparkle.framework and will not start"
[[ -z "$(entitled com.apple.security.get-task-allow)" ]] || refuse "the app would be published debuggable (get-task-allow)"
read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true; }
[[ "$(read_plist SUPublicEDKey)" == "$public_key" ]] || refuse "the build carries SUPublicEDKey $(read_plist SUPublicEDKey), expected $public_key"
expected_feed="https://github.com/$publish_repo/releases/latest/download/appcast.xml"
[[ "$(read_plist SUFeedURL)" == "$expected_feed" ]] || refuse "SUFeedURL is $(read_plist SUFeedURL), but releases go to $expected_feed"
[[ "$(read_plist CFBundleShortVersionString)" == "$version" ]] || refuse "the build carries version $(read_plist CFBundleShortVersionString), expected $version"
[[ "$(read_plist CFBundleVersion)" == "$build" ]] || refuse "the build carries build $(read_plist CFBundleVersion), expected $build"

# The check build 202 did not have: this very bundle is launched and asserted on (REQ-098).
# `codesign --verify --deep --strict` was content with 202, an app that could not start at all.
# This does not catch 202's own defect — GitHub's runners do not enforce library validation, so
# that build would launch here and still die on every Mac; the entitlement check above is what
# catches that one. This catches everything else that stops a release from running.
#
# It is launched twice. The runner was booted minutes ago and has just written a build, so the
# first launch on it pages most of AppKit and SwiftUI in from a cold virtual disk while Spotlight
# indexes that build: in repeat-smoke 45924758118 the main thread spent 2.9 s building the first
# window, 1.9 s of it asleep in the kernel's throttle_lowpri_io, and that launch's mainActorStall
# is a measurement of the runner. Every check but that one still holds on the first launch — it
# must start, open the fixture, take both edits, and exit cleanly with no other fault — and the
# second launch is held to all of them (ADR 0014).
say "launching the signed app, first launch on this runner (Scripts/smoke-test.sh)"
SMOKE_APP="$app" SMOKE_VERIFIER_EXTRA_ARGS="--allow-fault mainActorStall" ./Scripts/smoke-test.sh \
    || refuse "the signed app failed its first launch; nothing was published"
say "launching the signed app again, held to every check"
SMOKE_APP="$app" ./Scripts/smoke-test.sh || refuse "the signed app failed its smoke run; nothing was published"

# The disk image a person installs from: the app beside a link to Applications. hdiutil on hosted
# runners intermittently reports "Resource busy" (a Spotlight/XProtect race), so it is retried.
mkdir "$out/image"
ditto "$app" "$out/image/Markdown Editor.app"
ln -s /Applications "$out/image/Applications"
image="$out/Markdown-Editor.dmg"
for attempt in 1 2 3; do
    if hdiutil create -quiet -volname "Markdown Editor" -srcfolder "$out/image" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$image"; then
        break
    fi
    (( attempt < 3 )) || refuse "hdiutil could not create the disk image"
    sleep 10
done
hdiutil verify -quiet "$image"

# The Sparkle archive, from the app, signed with the derived update key. Before anything
# is published, Sparkle's own sign_update checks that signature with its own Ed25519 code (the key
# goes in on standard input), so a key or format mismatch stops here, not on installed copies.
archive="$out/Markdown-Editor-$version.zip"
ditto -c -k --keepParent "$app" "$archive"
signature="$(./Scripts/sparkle-key.sh sign "$archive")"
sign_update="$derived/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
./Scripts/sparkle-key.sh seed | "$sign_update" --verify "$archive" "$signature" --ed-key-file - >/dev/null \
    || refuse "Sparkle's sign_update does not accept the archive's signature"
length="$(stat -f %z "$archive")"
url="https://github.com/$publish_repo/releases/download/$tag/Markdown-Editor-$version.zip"
./Scripts/appcast.sh "$publish_repo" "$build" "$version" "$url" "$length" "$signature" > "$out/appcast.xml"

opening="It is not notarized by Apple. The first time you open it, macOS says it can't check the app: click **Done**, open **System Settings → Privacy & Security**, click **Open Anyway**, and confirm. After that it opens like any app, and updates itself."
notes="Markdown Editor $version, build $build. An installed copy updates itself to it.

To install by hand: download **Markdown-Editor.dmg** below, open it, and drag Markdown Editor to Applications. It needs macOS 27 or later. $opening

source-commit: $sha"

gh release create "$tag" --repo "$publish_repo" --target "$sha" --latest \
    --title "Markdown Editor $version" --notes "$notes" \
    "$image" "$archive" "$out/appcast.xml"
say "published $tag (build $build, commit $sha) to $publish_repo"

# Older releases go, their tags with them: all but the newest three.
gh release list --repo "$publish_repo" --limit 100 --json tagName,createdAt \
    --jq 'sort_by(.createdAt) | reverse | .[].tagName' | tail -n +"$((keep + 1))" | while read -r old; do
    [[ "$old" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    gh release delete "$old" --repo "$publish_repo" --yes --cleanup-tag
    say "pruned $old"
done
