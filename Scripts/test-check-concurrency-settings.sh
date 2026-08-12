#!/bin/bash
# REQ-088: fixture proof for the configuration gate.
set -euo pipefail

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
gate="$(dirname "$0")/check-concurrency-settings.sh"

cat > "$root/complete.txt" <<'EOF'
CONFIGURATION = Debug
SWIFT_STRICT_CONCURRENCY = complete
SWIFT_STRICT_CONCURRENCY = complete
CONFIGURATION = Release
SWIFT_STRICT_CONCURRENCY = complete
SWIFT_STRICT_CONCURRENCY = complete
EOF
"$gate" --settings-file "$root/complete.txt" >/dev/null

cat > "$root/incomplete.txt" <<'EOF'
CONFIGURATION = Debug
SWIFT_STRICT_CONCURRENCY = complete
SWIFT_STRICT_CONCURRENCY = complete
CONFIGURATION = Release
SWIFT_STRICT_CONCURRENCY = complete
EOF
if "$gate" --settings-file "$root/incomplete.txt" >/dev/null 2>&1; then
    echo "test-check-concurrency-settings: incomplete settings unexpectedly passed" >&2
    exit 1
fi

echo "check-concurrency-settings fixtures: PASS"
