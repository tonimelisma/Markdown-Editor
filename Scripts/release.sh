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
# The environment the workflow gives it:
#   SIGNING_IDENTITY     SHA-1 of the identity imported from CERTIFICATE_P12
#   SIGNING_KEYCHAIN     the keychain the workflow imported it into for this run
#   SPARKLE_PRIVATE_KEY  the EdDSA update key, handed to sign_update on standard input
#   RELEASE_REPOSITORY   owner/name the release is published to (default: GITHUB_REPOSITORY)
#   NOTARY_KEY_P8, NOTARY_KEY_ID, NOTARY_ISSUER_ID
#                        optional App Store Connect API key; with a Developer ID identity, the
#                        app and the disk image are notarized and stapled (VISION, Distribution)
#   GH_TOKEN, GITHUB_REPOSITORY
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

: "${SIGNING_IDENTITY:?the signing identity is needed}"
: "${SIGNING_KEYCHAIN:?the signing keychain is needed}"
: "${SPARKLE_PRIVATE_KEY:?the update key is needed}"
: "${GITHUB_REPOSITORY:?the repository is needed}"
publish_repo="${RELEASE_REPOSITORY:-$GITHUB_REPOSITORY}"
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

# The newest release, and whether this commit changes the app it holds. Each release's notes end
# with `source-commit: <sha>`, so this works when releases live in another repository too. The
# workflow runs one release at a time.
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

identity_name="$(security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" | awk -v sha="$SIGNING_IDENTITY" '$2 == sha { sub(/^[^"]*"/, ""); sub(/"$/, ""); print; exit }')"
[[ -n "$identity_name" ]] || refuse "the signing identity is not in the keychain"
notarize=0
if [[ "$identity_name" == "Developer ID Application:"* && -n "${NOTARY_KEY_P8:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
    notarize=1
fi
say "signing with \"${identity_name%% (*}\"; notarize=$notarize"

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
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    PROVISIONING_PROFILE_SPECIFIER= \
    OTHER_CODE_SIGN_FLAGS="--keychain=$SIGNING_KEYCHAIN $timestamp_flag" \
    CURRENT_PROJECT_VERSION="$build" \
    MARKETING_VERSION="$version" \
    build

app="$derived/Build/Products/Release/Markdown Editor.app"
plist="$app/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict "$app"
read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true; }
[[ -n "$(read_plist SUPublicEDKey)" ]] || refuse "SUPublicEDKey is empty: installed copies could not check this build (run Scripts/release-setup.sh once)"
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
/usr/bin/codesign --sign "$SIGNING_IDENTITY" --keychain "$SIGNING_KEYCHAIN" "$timestamp_flag" "$image"
/usr/bin/codesign --verify "$image"
hdiutil verify -quiet "$image"
if (( notarize )); then
    notary "$image"
    xcrun stapler staple "$image"
fi

# The Sparkle archive, from the (stapled) app. The update key goes in on standard input.
archive="$out/Markdown-Editor-$version.zip"
ditto -c -k --keepParent "$app" "$archive"
sign_update="$derived/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
signed="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sign_update" --ed-key-file - "$archive")"
signature="$(printf '%s' "$signed" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
[[ -n "$signature" ]] || refuse "sign_update gave no signature"
length="$(stat -f %z "$archive")"
url="https://github.com/$publish_repo/releases/download/$tag/Markdown-Editor-$version.zip"
./Scripts/appcast.sh "$publish_repo" "$build" "$version" "$url" "$length" "$signature" > "$out/appcast.xml"

if (( notarize )); then
    opening="It is signed with a Developer ID and notarized by Apple."
else
    opening="It is signed for development, not notarized. The first time you open it, macOS says it can't check the app: click **Done**, open **System Settings → Privacy & Security**, click **Open Anyway**, and confirm. After that it opens like any app, and updates itself."
fi
notes="Markdown Editor $version, build $build. An installed copy updates itself to it.

To install by hand: download **Markdown-Editor.dmg** below, open it, and drag Markdown Editor to Applications. It needs macOS 27 or later. $opening

source-commit: $sha"

# A release in this repository is tagged at the commit; one in another repository is tagged at
# that repository's default branch, and its notes name the commit. (macOS /bin/bash is 3.2, where
# an empty array under `set -u` is an error, hence the ${x+...} form.)
target=()
if [[ "$publish_repo" == "$GITHUB_REPOSITORY" ]]; then
    target=(--target "$sha")
fi
gh release create "$tag" --repo "$publish_repo" ${target[@]+"${target[@]}"} --latest \
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
