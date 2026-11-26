#!/bin/bash
# The owner's one-time release setup, on the Mac, in a clean checkout of `main`:
#   Scripts/release-setup.sh
# It is the only step of the release path that needs the owner's Mac, because the signing
# certificate's private key lives in its login keychain. It builds and installs nothing.
#
# 1. Makes the app's EdDSA update key in the login keychain with Sparkle's own generate_keys
#    (from Sparkle's release archive, checked by SHA-256), under the keychain account
#    net.melisma.Markdown-Editor, or reuses the one already there. Its own account, because
#    generate_keys's default account is shared by every app signed that way.
# 2. Creates the repository environment `release` and sets its secrets with the owner's own `gh`
#    login: SPARKLE_PRIVATE_KEY, CERTIFICATE_P12 and CERTIFICATE_PASSWORD. The certificate is the
#    team's newest valid "Developer ID Application" identity if there is one, otherwise its newest
#    valid "Apple Development" one (macOS asks to allow the export).
# 3. Commits the public key as the Release configuration's SPARKLE_PUBLIC_ED_KEY and opens its
#    pull request.
# Every secret value goes from a private temporary folder, removed however the script ends, to
# `gh secret set` on standard input: nothing is printed, logged or committed. Safe to run again.
#
# Notarization (optional, needs a Developer ID): set NOTARY_KEY_P8 (the .p8's contents),
# NOTARY_KEY_ID and NOTARY_ISSUER_ID in the same environment with `gh secret set … --env release`.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
repo="${RELEASE_SETUP_REPO:-tonimelisma/Markdown-Editor}"
project="$repo_root/Markdown Editor.xcodeproj/project.pbxproj"
login_keychain="$HOME/Library/Keychains/login.keychain-db"
branch="chore/sparkle-update-key"
key_account="net.melisma.Markdown-Editor"
sparkle_version="2.10.1" # matches Package.resolved
sparkle_sha256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"

say() { echo "release-setup: $*"; }
refuse() {
    echo "release-setup: $*" >&2
    exit 1
}

[[ "$(uname -s)" == Darwin ]] || refuse "this runs on the owner's Mac"
[[ "$(./Scripts/sparkle-advisories.sh version 2>/dev/null || true)" == "$sparkle_version" ]] \
    || refuse "Package.resolved does not pin Sparkle $sparkle_version; update this script with the pin"
team="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM = \([A-Z0-9]*\);/\1/p' "$project" | sort -u)"
[[ "$team" =~ ^[A-Z0-9]{10}$ ]] || refuse "the project names no single DEVELOPMENT_TEAM"
gh auth status >/dev/null 2>&1 || refuse "gh is not signed in (run: gh auth login)"
[[ "$(git -C "$repo_root" symbolic-ref --short -q HEAD)" == main ]] || refuse "check out main first"
[[ -z "$(git -C "$repo_root" status --porcelain)" ]] || refuse "the checkout is dirty"
git -C "$repo_root" pull -q --ff-only origin main || refuse "git pull failed"

work="$(mktemp -d)"
chmod 700 "$work"
trap 'rm -rf "$work"; git -C "$repo_root" checkout -q main 2>/dev/null || true' EXIT

# 1. The update key.
curl -sSfL -o "$work/sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz" \
    || refuse "could not download Sparkle $sparkle_version"
echo "$sparkle_sha256  $work/sparkle.tar.xz" | shasum -a 256 -c - >/dev/null || refuse "Sparkle's archive failed its checksum"
mkdir "$work/sparkle"
tar -xJf "$work/sparkle.tar.xz" -C "$work/sparkle" ./bin/generate_keys
generate_keys="$work/sparkle/bin/generate_keys"
if ! public_key="$("$generate_keys" --account "$key_account" -p 2>/dev/null)" || [[ -z "$public_key" ]]; then
    "$generate_keys" --account "$key_account" >/dev/null
    public_key="$("$generate_keys" --account "$key_account" -p)"
fi
public_key="$(printf '%s' "$public_key" | tr -d '[:space:]')"
[[ "$public_key" =~ ^[A-Za-z0-9+/=]{40,}$ ]] || refuse "could not read the public update key"
say "update key ready (public key $public_key)"

# 2. The environment and its secrets.
gh api -X PUT "repos/$repo/environments/release" >/dev/null
secret() { # <name> <file>
    gh secret set "$1" --env release --repo "$repo" < "$2" >/dev/null
    say "secret $1 set"
}
"$generate_keys" --account "$key_account" -x "$work/sparkle.key" >/dev/null
secret SPARKLE_PRIVATE_KEY "$work/sparkle.key"

# The identity: of the team's valid code-signing identities (Apple's revocation service asked,
# since a revoked certificate still reads as valid in a keychain), the newest Developer ID
# Application one, else the newest Apple Development one.
security find-certificate -a -Z -p "$login_keychain" > "$work/certs.pem"
certificate_of() { # <sha-1>: its PEM
    awk -v sha="$1" '
        /^SHA-1 hash:/ { keep = ($3 == sha) }
        keep && /BEGIN CERTIFICATE/ { inside = 1 }
        keep && inside { print }
        keep && /END CERTIFICATE/ { exit }' "$work/certs.pem"
}
choose() { # <identity kind prefix>: prints the newest valid SHA-1, or nothing
    local kind="$1" chosen="" chosen_start=0 sha subject start
    while read -r sha; do
        certificate_of "$sha" > "$work/candidate.pem"
        subject="$(openssl x509 -noout -subject < "$work/candidate.pem" 2>/dev/null || true)"
        [[ "$subject" == *"OU=$team"* || "$subject" == *"OU = $team"* ]] || continue
        security verify-cert -q -c "$work/candidate.pem" -p codeSign -R ocsp -R require >/dev/null 2>&1 || continue
        start="$(openssl x509 -noout -startdate < "$work/candidate.pem" | sed 's/^notBefore=//')"
        start="$(python3 -I -c 'import calendar, sys, time; print(calendar.timegm(time.strptime(" ".join(sys.argv[1].split()), "%b %d %H:%M:%S %Y %Z")))' "$start")"
        if (( start > chosen_start )); then
            chosen="$sha"
            chosen_start="$start"
        fi
    done < <(security find-identity -v -p codesigning "$login_keychain" | awk -v kind="\"$kind" 'index($0, kind) { print $2 }')
    echo "$chosen"
}
chosen="$(choose "Developer ID Application")"
kind="Developer ID Application"
if [[ -z "$chosen" ]]; then
    chosen="$(choose "Apple Development")"
    kind="Apple Development"
fi
[[ -n "$chosen" ]] || refuse "no valid Developer ID Application or Apple Development identity for team $team (make one in Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates)"

# The login keychain exports every identity at once, so they go into a keychain of this run's own,
# every other identity is deleted there, and that keychain is exported.
openssl rand -base64 24 | tr -d '\n' > "$work/p12-password"
kc="$work/export.keychain-db"
kc_password="$(openssl rand -hex 16)"
security export -k "$login_keychain" -t identities -f pkcs12 -P "$(cat "$work/p12-password")" -o "$work/all.p12" >/dev/null
security create-keychain -p "$kc_password" "$kc"
security unlock-keychain -p "$kc_password" "$kc"
security import "$work/all.p12" -k "$kc" -P "$(cat "$work/p12-password")" >/dev/null
while read -r sha; do
    [[ "$sha" == "$chosen" ]] || security delete-identity -Z "$sha" "$kc" >/dev/null
done < <(security find-identity "$kc" | awk '/^ *[0-9]+\)/ && !seen[$2]++ { print $2 }')
security export -k "$kc" -t identities -f pkcs12 -P "$(cat "$work/p12-password")" -o "$work/identity.p12" >/dev/null
security delete-keychain "$kc"
base64 < "$work/identity.p12" | tr -d '\n' > "$work/identity.p12.base64"
secret CERTIFICATE_P12 "$work/identity.p12.base64"
secret CERTIFICATE_PASSWORD "$work/p12-password"
say "certificate: $kind ($chosen)"

# 3. The public key in the Release configuration, by pull request.
if grep -q "SPARKLE_PUBLIC_ED_KEY = \"$public_key\";" "$project"; then
    say "the public key is already committed"
else
    git -C "$repo_root" checkout -q -B "$branch"
    sed -i '' "s|SPARKLE_PUBLIC_ED_KEY = \"[^\"]*\";|SPARKLE_PUBLIC_ED_KEY = \"$public_key\";|" "$project"
    [[ "$(grep -c "SPARKLE_PUBLIC_ED_KEY = \"$public_key\";" "$project")" == 1 ]] || refuse "the project's SPARKLE_PUBLIC_ED_KEY was not updated exactly once"
    git -C "$repo_root" commit -q -m "Carry the Sparkle update key's public half in Release builds" -- "$project"
    git -C "$repo_root" push -q -u --force origin "$branch" # this script's own branch
    url="$(gh pr list --repo "$repo" --head "$branch" --state open --json url --jq '.[0].url // empty')"
    if [[ -z "$url" ]]; then
        url="$(gh pr create --repo "$repo" --head "$branch" --base main \
            --title "Carry the Sparkle update key's public half in Release builds" \
            --body "Made by Scripts/release-setup.sh. The private half is in the owner's login keychain (account $key_account) and the environment \`release\`.")"
    fi
    say "public key pull request: $url (merge it once CI passes)"
fi

say "done. Once that pull request is merged, CI publishes the first release; install it once from https://github.com/$repo/releases/latest/download/Markdown-Editor.dmg and it updates itself from then on"
