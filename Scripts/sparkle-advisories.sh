#!/bin/bash
# Fails when the Sparkle version the project pins has known advisories in the OSV database, so
# no build with a vulnerable updater is published (Scripts/release.sh runs it before building).
#   Scripts/sparkle-advisories.sh           ask OSV about the pinned version
#   Scripts/sparkle-advisories.sh version   print the pinned version
# A failed request fails the check: an unanswered question never reads as "no advisories".
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
resolved="${PACKAGE_RESOLVED:-$repo_root/Markdown Editor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved}"

version="$(python3 -I -c '
import json, sys
pins = [p for p in json.load(open(sys.argv[1]))["pins"] if p.get("identity") == "sparkle"]
if len(pins) != 1 or not pins[0].get("state", {}).get("version"):
    sys.exit("sparkle-advisories: Package.resolved pins no Sparkle version")
print(pins[0]["state"]["version"])
' "$resolved")"

if [[ "${1:-}" == version ]]; then
    echo "$version"
    exit 0
fi

body="$(printf '{"package":{"name":"github.com/sparkle-project/Sparkle","ecosystem":"SwiftURL"},"version":"%s"}' "$version")"
if ! result="$(curl -fsS --max-time 30 -X POST https://api.osv.dev/v1/query -H 'Content-Type: application/json' -d "$body")"; then
    echo "sparkle-advisories: OSV did not answer for Sparkle $version" >&2
    exit 1
fi
if [[ "$(printf '%s' "$result" | tr -d '[:space:]')" != "{}" ]]; then
    echo "sparkle-advisories: Sparkle $version has known advisories:" >&2
    printf '%s\n' "$result" >&2
    exit 1
fi
echo "sparkle-advisories: none for Sparkle $version"
