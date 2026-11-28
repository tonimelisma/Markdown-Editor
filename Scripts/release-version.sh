#!/bin/bash
# The version a release is published as, x.y.z (ADR 0010):
#   Scripts/release-version.sh <series x.y> [<newest published version x.y.z>]
# The series is the project's MARKETING_VERSION; a commit that changes it starts a new major or
# minor version. Each release takes the next patch of its series; a series newer than the newest
# published version starts at x.y.0, and the first release ever is <series>.0. A series older than
# one already published is refused: versions only rise. Tested by Scripts/test-release-scripts.sh.
set -euo pipefail

refuse() {
    echo "release-version: $*" >&2
    exit 1
}
series="${1:?usage: release-version.sh <series x.y> [<newest published x.y.z>]}"
last="${2:-}"
[[ "$series" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || refuse "the series $series isn't x.y"
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
if [[ -z "$last" ]]; then
    echo "$major.$minor.0"
    exit 0
fi
[[ "$last" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || refuse "the published version $last isn't x.y.z"
last_major="${BASH_REMATCH[1]}"
last_minor="${BASH_REMATCH[2]}"
last_patch="${BASH_REMATCH[3]}"
if (( major == last_major && minor == last_minor )); then
    echo "$major.$minor.$((last_patch + 1))"
elif (( major > last_major || (major == last_major && minor > last_minor) )); then
    echo "$major.$minor.0"
else
    refuse "the series $series is older than the published $last"
fi
