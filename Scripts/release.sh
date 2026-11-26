#!/bin/bash
# Builds, signs and publishes the checked-out main commit as an update (docs/DECISIONS.md,
# "Cloud-first development"). `.github/workflows/release.yml` runs it on GitHub's macOS runner
# once that commit's CI passed; it publishes to GitHub, so it is not run by hand.
#
# A release is made only when the app changed since the newest release (anything under
# `Markdown Editor/` or `Markdown Editor.xcodeproj/`). It is v<x.y.z>, the next version of the
# project's MARKETING_VERSION series (Scripts/release-version.sh), with CFBundleVersion the commit
# count, the number Sparkle compares. It holds the disk image a person installs from
# (Markdown-Editor.dmg), the Sparkle archive, and the feed that names it (Scripts/appcast.sh). It is
# refused while the pinned Sparkle has known advisories (Scripts/sparkle-advisories.sh). It is
# marked latest, so releases/latest/download/appcast.xml always names the newest build. Only the
# newest three releases are kept.
#
# Nothing here needs the owner's Mac (docs/DECISIONS.md, 2026-11-26, "No Mac, not even once").
#
# The environment the workflow gives it:
#   SPARKLE_SEED         the secret the update key is derived from (Scripts/sparkle-key.sh); its
#                        public half is stamped into the build as SUPublicEDKey
#   OPENSSL              an OpenSSL 3 binary for Scripts/sparkle-key.sh
#   SIGNING_IDENTITY     optional: SHA-1 of an identity imported from CERTIFICATE_P12, and
#   SIGNING_KEYCHAIN     the keychain it is in. Without them the app is signed ad hoc. Sparkle
#                        accepts an update whose EdDSA key is unchanged whatever its signing
#                        identity (SUUpdateValidator), so a certificate can be added later.
#   NOTARY_KEY_P8, NOTARY_KEY_ID, NOTARY_ISSUER_ID
#                        optional App Store Connect API key; with a Developer ID identity, the
#                        app and the disk image are notarized and stapled (VISION, Distribution)
#   GH_TOKEN, GITHUB_REPOSITORY
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

: "${SPARKLE_SEED:?the seed of the update key is needed}"
: "${GITHUB_REPOSITORY:?the repository is needed}"
signing_identity="${SIGNING_IDENTITY:--}"
publish_repo="$GITHUB_REPOSITORY"
keep=3
project="Markdown Editor.xcodeproj"
app_paths=("Markdown Editor" "Markdown Editor.xcodeproj")

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
keychain_flag=""
identity_name="ad hoc"
if [[ "$signing_identity" != "-" ]]; then
    : "${SIGNING_KEYCHAIN:?a signing identity needs its keychain}"
    keychain_flag="--keychain=$SIGNING_KEYCHAIN"
    identity_name="$(security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" | awk -v sha="$signing_identity" '$2 == sha { sub(/^[^"]*"/, ""); sub(/"$/, ""); print; exit }')"
    [[ -n "$identity_name" ]] || refuse "the signing identity is not in the keychain"
fi
notarize=0
if [[ "$identity_name" == "Developer ID Application:"* && -n "${NOTARY_KEY_P8:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
    notarize=1
fi
say "signing: ${identity_name%% (*}; notarize=$notarize; update key $public_key"

derived="$repo_root/build/ReleaseDerivedData"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

timestamp_flag="--timestamp=none"
if (( notarize )); then
    timestamp_flag="--timestamp"
fi
xcodebuild \
    -project "$project" \
    -scheme "Markdown Editor" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$signing_identity" \
    DEVELOPMENT_TEAM= \
    PROVISIONING_PROFILE_SPECIFIER= \
    OTHER_CODE_SIGN_FLAGS="$keychain_flag $timestamp_flag" \
    SPARKLE_PUBLIC_ED_KEY="$public_key" \
    CURRENT_PROJECT_VERSION="$build" \
    MARKETING_VERSION="$version" \
    build

app="$derived/Build/Products/Release/Markdown Editor.app"
plist="$app/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict "$app"
read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true; }
[[ "$(read_plist SUPublicEDKey)" == "$public_key" ]] || refuse "the build carries SUPublicEDKey $(read_plist SUPublicEDKey), expected $public_key"
expected_feed="https://github.com/$publish_repo/releases/latest/download/appcast.xml"
[[ "$(read_plist SUFeedURL)" == "$expected_feed" ]] || refuse "SUFeedURL is $(read_plist SUFeedURL), but releases go to $expected_feed"
[[ "$(read_plist CFBundleShortVersionString)" == "$version" ]] || refuse "the build carries version $(read_plist CFBundleShortVersionString), expected $version"
[[ "$(read_plist CFBundleVersion)" == "$build" ]] || refuse "the build carries build $(read_plist CFBundleVersion), expected $build"

notary() { # <file>
    local key="$out/notary.p8"
    printf '%s' "$NOTARY_KEY_P8" > "$key"
    xcrun notarytool submit "$1" --key "$key" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait --timeout 30m
    rm -f "$key"
}
if (( notarize )); then
    ditto -c -k --keepParent "$app" "$out/notarize.zip"
    notary "$out/notarize.zip"
    xcrun stapler staple "$app"
    rm -f "$out/notarize.zip"
fi

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
# The disk image is signed only with a real identity; an ad hoc signature on it would add nothing.
if [[ "$signing_identity" != "-" ]]; then
    /usr/bin/codesign --sign "$signing_identity" $keychain_flag "$timestamp_flag" "$image"
    /usr/bin/codesign --verify "$image"
fi
hdiutil verify -quiet "$image"
if (( notarize )); then
    notary "$image"
    xcrun stapler staple "$image"
fi

# The Sparkle archive, from the (stapled) app, signed with the derived update key. Before anything
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

if (( notarize )); then
    opening="It is signed with a Developer ID and notarized by Apple."
else
    opening="It is not notarized by Apple. The first time you open it, macOS says it can't check the app: click **Done**, open **System Settings → Privacy & Security**, click **Open Anyway**, and confirm. After that it opens like any app, and updates itself."
fi
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
