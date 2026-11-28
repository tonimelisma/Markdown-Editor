#!/bin/bash
# The app's Sparkle update key, derived from one secret: no keychain, no Mac, no key file.
#   SPARKLE_SEED=… Scripts/sparkle-key.sh public        the public key (SUPublicEDKey), base64
#   SPARKLE_SEED=… Scripts/sparkle-key.sh sign <file>   the file's EdDSA signature, base64
#   SPARKLE_SEED=… Scripts/sparkle-key.sh seed          the private key in Sparkle's own format (the
#                                                       32-byte seed, base64), for piping into
#                                                       Sparkle's sign_update; never print it
#
# SPARKLE_SEED is a long random password whose master copy is the secret
# markdown-editor-sparkle-seed in the release environment's Azure Key Vault; the release workflow fetches it
# into its environment (docs/development.md). The Ed25519 private key is SHA-256 of a fixed label
# and that password, so every release derives the same key and nothing else needs storing.
# Sparkle's EdDSA is standard Ed25519 over the archive's bytes, which is what OpenSSL 3 computes.
# The key exists only in a private temporary folder, removed however the script ends.
# OPENSSL names an OpenSSL 3 binary (macOS's own LibreSSL has no Ed25519 signing).
# Tested by Scripts/test-release-scripts.sh.
set -euo pipefail

openssl="${OPENSSL:-openssl}"
refuse() {
    echo "sparkle-key: $*" >&2
    exit 1
}
seed="${SPARKLE_SEED:-}"
[[ ${#seed} -ge 32 ]] || refuse "SPARKLE_SEED must be set to a random password of at least 32 characters"
"$openssl" version 2>/dev/null | grep -q '^OpenSSL [3-9]' || refuse "$openssl is not OpenSSL 3 or later"

work="$(mktemp -d)"
chmod 700 "$work"
trap 'rm -rf "$work"' EXIT
umask 077
# PKCS#8 wrapping of a raw Ed25519 seed (RFC 8410): a fixed 16-byte prefix, then the 32 bytes.
{
    printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x70\x04\x22\x04\x20'
    printf 'markdown-editor/sparkle-ed25519/v1\n%s' "$seed" | "$openssl" dgst -sha256 -binary
} > "$work/key.der"
"$openssl" pkey -inform DER -in "$work/key.der" -out "$work/key.pem"

case "${1:-}" in
    seed)
        "$openssl" pkey -in "$work/key.pem" -outform DER | tail -c 32 | "$openssl" base64 -A
        echo
        ;;
    public)
        # The last 32 bytes of the SubjectPublicKeyInfo are the raw public key.
        "$openssl" pkey -in "$work/key.pem" -pubout -outform DER | tail -c 32 | "$openssl" base64 -A
        echo
        ;;
    sign)
        file="${2:?usage: sparkle-key.sh sign <file>}"
        [[ -f "$file" ]] || refuse "no file $file"
        "$openssl" pkeyutl -sign -inkey "$work/key.pem" -rawin -in "$file" -out "$work/signature"
        [[ "$(wc -c < "$work/signature" | tr -d ' ')" == 64 ]] || refuse "the signature is not 64 bytes"
        "$openssl" base64 -A -in "$work/signature"
        echo
        ;;
    *)
        refuse "usage: sparkle-key.sh public | sign <file> | seed"
        ;;
esac
