#!/bin/bash
# COR-61: Phase 1 manifest schema failure/liveness fixtures.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
gate="$repo_root/Scripts/check-falsification.sh"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/docs" "$root/Falsification" "$root/Markdown Editor"

cat >"$root/docs/REQUIREMENTS.md" <<'EOF'
| REQ-001 | Fixture requirement | COR-61 | Done | Markdown Editor/Fixture.swift | test fixtureProof |
EOF
printf 'return .bounded(range: changed)\n' >"$root/Markdown Editor/Fixture.swift"

write_manifest() {
    local find="$1" replace="$2" expect_red="$3" file="${4:-Markdown Editor/Fixture.swift}"
    jq -n --arg find "$find" --arg replace "$replace" --arg expect_red "$expect_red" --arg file "$file" \
        '{requirement:"REQ-001",mutations:[{rationale:"The fixture requires bounded edits.",file:$file,find:$find,replace:$replace,expect_red:[$expect_red]}]}' \
        >"$root/Falsification/REQ-001.json"
}

expect_failure() {
    local name="$1" expected="$2"
    shift
    shift
    local output
    if output="$("$@" 2>&1)"; then
        echo "test-check-falsification: $name unexpectedly passed" >&2
        exit 1
    fi
    if [[ "$output" != *"$expected"* ]]; then
        echo "test-check-falsification: $name failed for an unexpected reason" >&2
        echo "$output" >&2
        exit 1
    fi
}

write_manifest 'return .missing()' 'return .bounded()' fixtureProof
expect_failure 'find matches zero times' 'find must match exactly once' "$gate" --all --fixture-root "$root"

write_manifest 'return .bounded(range: changed)' 'fatalError' fixtureProof
expect_failure 'degenerate replacement' 'degenerate kill mutation' "$gate" --all --fixture-root "$root"

printf 'return .bounded(range: changed)\nreturn .bounded(range: changed)\n' >"$root/Markdown Editor/Fixture.swift"
write_manifest 'return .bounded(range: changed)' 'return .full(range: changed)' fixtureProof
expect_failure 'find matches twice' 'find must match exactly once' "$gate" --all --fixture-root "$root"
printf 'return .bounded(range: changed)\n' >"$root/Markdown Editor/Fixture.swift"

write_manifest 'return .bounded(range: changed)' 'return .full(range: changed)' ''
expect_failure 'missing expected red proof' 'expect_red must name at least one proof' "$gate" --all --fixture-root "$root"

write_manifest 'return .bounded(range: changed)' 'return .full(range: changed)' fixtureProof
jq '.mutations[0].expect_red = []' "$root/Falsification/REQ-001.json" >"$root/Falsification/REQ-001.json.tmp"
mv "$root/Falsification/REQ-001.json.tmp" "$root/Falsification/REQ-001.json"
expect_failure 'empty expected red array' 'expect_red must name at least one proof' "$gate" --all --fixture-root "$root"

write_manifest 'return .bounded(range: changed)' 'return .full(range: changed)' fixtureProof
jq '.mutations[0].file = 7' "$root/Falsification/REQ-001.json" >"$root/Falsification/REQ-001.json.tmp"
mv "$root/Falsification/REQ-001.json.tmp" "$root/Falsification/REQ-001.json"
expect_failure 'malformed mutation field type' 'target file must be a string' "$gate" --all --fixture-root "$root"

write_manifest 'return .bounded(range: changed)' 'return .full(range: changed)' fixtureProof /tmp/Fixture.swift
expect_failure 'absolute mutation path' 'target file must be a relative in-repository path' "$gate" --all --fixture-root "$root"

write_manifest 'return .bounded(range: changed)' 'return .full(range: changed)' fixtureProof '../Markdown Editor/Fixture.swift'
expect_failure 'traversal mutation path' 'target file must be a relative in-repository path' "$gate" --all --fixture-root "$root"

cat >>"$root/docs/REQUIREMENTS.md" <<'EOF'
| REQ-002 | Unmanifested requirement | COR-61 | Done | Markdown Editor/Fixture.swift | test fixtureProof |
EOF
write_manifest 'return .bounded(range: changed)' 'return .full(range: changed)' fixtureProof
expect_failure 'unmanifested Done requirement' 'Done requirement has no falsification manifest' "$gate" --all --fixture-root "$root"

sed -i '' '/| REQ-002 /d' "$root/docs/REQUIREMENTS.md"
"$gate" --all --fixture-root "$root" >/dev/null

echo "test-check-falsification: PASS (schema failure and liveness fixtures observed)"
