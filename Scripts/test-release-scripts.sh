#!/bin/bash
# The release scripts' pure parts, proved to discriminate: Scripts/release-version.sh (which
# version a release takes) and Scripts/appcast.sh (the feed installed copies read). Portable; run
# by Scripts/check.sh everywhere, including cloud sessions. The rest of the release path needs
# macOS, the certificate and GitHub, and is proved only by a published release (docs/ROADMAP.md).
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

if (( failures > 0 )); then
    echo "test-release-scripts: $failures failure(s)" >&2
    exit 1
fi
echo "test-release-scripts: all cases discriminated"
