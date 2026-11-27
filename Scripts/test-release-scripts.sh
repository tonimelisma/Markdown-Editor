#!/bin/bash
# The release scripts' pure parts, proved to discriminate: Scripts/release-version.sh (which
# version a release takes) and Scripts/appcast.sh (the feed installed copies read). Portable; run
# by Scripts/check.sh everywhere, including cloud sessions. The signing is proved separately, and on
# macOS, by Scripts/test-adhoc-harden.sh; what is left — the certificate, notarization and GitHub —
# is proved only by a published release that someone has installed and opened (docs/ROADMAP.md).
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
version="$repo_root/Scripts/release-version.sh"
appcast="$repo_root/Scripts/appcast.sh"
failures=0

fail() {
    echo "FAIL $*" >&2
    failures=$((failures + 1))
}
expect_version() { # <expected> <args...>
    local expected="$1" actual
    shift
    if ! actual="$("$version" "$@" 2>/dev/null)"; then
        fail "release-version $*: refused, expected $expected"
    elif [[ "$actual" != "$expected" ]]; then
        fail "release-version $*: got $actual, expected $expected"
    fi
}
expect_version_refused() { # <args...>
    if "$version" "$@" >/dev/null 2>&1; then
        fail "release-version $*: accepted, expected a refusal"
    fi
}

expect_version 1.0.0 1.0
expect_version 1.0.1 1.0 1.0.0
expect_version 1.0.10 1.0 1.0.9
expect_version 1.1.0 1.1 1.0.7
expect_version 2.0.0 2.0 1.9.3
expect_version_refused 1.0 1.1.0
expect_version_refused 1.0 2.0.0
expect_version_refused 1 1.0.0
expect_version_refused 1.0 1.0
expect_version_refused 01.0

repo="owner/Name"
url="https://github.com/$repo/releases/download/v1.2.3/Markdown-Editor-1.2.3.zip"
signature="QUJDRA+/xyz=="
if ! feed="$("$appcast" "$repo" 42 1.2.3 "$url" 1234 "$signature" 2>/dev/null)"; then
    fail "appcast: refused a valid build"
else
    # The feed is well-formed XML and carries exactly the values Sparkle compares and checks.
    if ! fields="$(printf '%s' "$feed" | python3 -I -c '
import sys, xml.etree.ElementTree as ET
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
item = ET.fromstring(sys.stdin.read()).find("channel/item")
enc = item.find("enclosure")
print(item.find("sparkle:version", ns).text, item.find("sparkle:shortVersionString", ns).text,
      enc.get("url"), enc.get("length"), enc.get("{%s}edSignature" % ns["sparkle"]))
')"; then
        fail "appcast: the feed is not parseable XML"
    elif [[ "$fields" != "42 1.2.3 $url 1234 $signature" ]]; then
        fail "appcast: the feed carries [$fields]"
    fi
fi
expect_appcast_refused() { # <reason> <args...>
    local reason="$1"
    shift
    if "$appcast" "$@" >/dev/null 2>&1; then
        fail "appcast accepted $reason"
    fi
}
expect_appcast_refused "a zero build" "$repo" 0 1.2.3 "$url" 1234 "$signature"
expect_appcast_refused "a two-part version" "$repo" 42 1.2 "$url" 1234 "$signature"
expect_appcast_refused "an archive in another release" "$repo" 42 1.2.4 "$url" 1234 "$signature"
expect_appcast_refused "an archive in another repository" other/Name 42 1.2.3 "$url" 1234 "$signature"
expect_appcast_refused "a plain-HTTP archive" "$repo" 42 1.2.3 "${url/https:/http:}" 1234 "$signature"
expect_appcast_refused "a URL needing XML escaping" "$repo" 42 1.2.3 "$url?a=1&b=2" 1234 "$signature"
expect_appcast_refused "a non-base64 signature" "$repo" 42 1.2.3 "$url" 1234 'abc"/>'
expect_appcast_refused "an empty length" "$repo" 42 1.2.3 "$url" "" "$signature"

# The update key (Scripts/sparkle-key.sh). Installed copies trust one public key forever, so the
# same password must always give the same key, a different one a different key, and a signature
# must verify under an implementation other than the one that made it (Python's cryptography,
# where installed; Sparkle's own check runs in every release before anything is published).
key="$repo_root/Scripts/sparkle-key.sh"
# macOS's own openssl is LibreSSL, which cannot sign with Ed25519; prefer Homebrew's OpenSSL 3.
if ! "${OPENSSL:-openssl}" version 2>/dev/null | grep -q '^OpenSSL [3-9]'; then
    candidate="$(brew --prefix openssl@3 2>/dev/null || true)/bin/openssl"
    [[ -x "$candidate" ]] && export OPENSSL="$candidate"
fi
if ! "${OPENSSL:-openssl}" version 2>/dev/null | grep -q '^OpenSSL [3-9]'; then
    echo "test-release-scripts: no OpenSSL 3 here; the update-key cases run in CI's Linux job"
    if (( failures > 0 )); then
        echo "test-release-scripts: $failures failure(s)" >&2
        exit 1
    fi
    echo "test-release-scripts: all cases discriminated"
    exit 0
fi
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
printf 'an archive\n' > "$work/archive"
seed_a="test-seed-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
seed_b="test-seed-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
pub_a="$(SPARKLE_SEED="$seed_a" "$key" public 2>/dev/null)" || fail "sparkle-key public refused a valid seed"
[[ "$(SPARKLE_SEED="$seed_a" "$key" public 2>/dev/null)" == "$pub_a" ]] || fail "sparkle-key public is not deterministic"
[[ "$(SPARKLE_SEED="$seed_b" "$key" public 2>/dev/null)" != "$pub_a" ]] || fail "sparkle-key gives two seeds one key"
[[ "$(python3 -I -c 'import base64, sys; print(len(base64.b64decode(sys.argv[1])))' "$pub_a" 2>/dev/null)" == 32 ]] || fail "sparkle-key public is not a 32-byte key"
SPARKLE_SEED="short" "$key" public >/dev/null 2>&1 && fail "sparkle-key accepted a short seed"
env -u SPARKLE_SEED "$key" public >/dev/null 2>&1 && fail "sparkle-key ran without a seed"
signature="$(SPARKLE_SEED="$seed_a" "$key" sign "$work/archive" 2>/dev/null)" || fail "sparkle-key sign failed"
seed64="$(SPARKLE_SEED="$seed_a" "$key" seed 2>/dev/null)" || fail "sparkle-key seed failed"
if python3 -c 'import cryptography' 2>/dev/null; then
    verify() { # <public key> <signature> <file> <seed base64>: exit 0 when the signature verifies
        python3 -I - "$@" <<'PY'
import base64, sys
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
public, signature, path, seed = sys.argv[1:5]
derived = Ed25519PrivateKey.from_private_bytes(base64.b64decode(seed)).public_key()
raw = derived.public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
if base64.b64encode(raw).decode() != public:
    sys.exit("the seed does not give the public key")
try:
    Ed25519PublicKey.from_public_bytes(base64.b64decode(public)).verify(base64.b64decode(signature), open(path, "rb").read())
except InvalidSignature:
    sys.exit("invalid signature")
PY
    }
    verify "$pub_a" "$signature" "$work/archive" "$seed64" 2>/dev/null || fail "the signature does not verify independently"
    printf 'another archive\n' > "$work/tampered"
    verify "$pub_a" "$signature" "$work/tampered" "$seed64" 2>/dev/null && fail "a signature verified for a different file"
else
    echo "test-release-scripts: python3 cryptography absent; independent signature check skipped"
fi

if (( failures > 0 )); then
    echo "test-release-scripts: $failures failure(s)" >&2
    exit 1
fi
echo "test-release-scripts: all cases discriminated"
