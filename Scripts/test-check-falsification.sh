#!/bin/bash
# COR-61: Phase 1 manifest schema failure/liveness fixtures.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
gate="$repo_root/Scripts/check-falsification.sh"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/docs" "$root/Falsification" "$root/Markdown Editor" "$root/Markdown EditorTests"

cat >"$root/Package.swift" <<'EOF'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fixture",
    products: [.library(name: "Fixture", targets: ["Fixture"])],
    targets: [
        .target(name: "Fixture", path: "Markdown Editor"),
        .testTarget(name: "FixtureTests", dependencies: ["Fixture"], path: "Markdown EditorTests"),
    ]
)
EOF

cat >"$root/Markdown Editor/Fixture.swift" <<'EOF'
public func fixtureValue() -> Int {
    // return .bounded(range: changed)
    return 1
}
EOF

cat >"$root/Markdown Editor/Implemented.swift" <<'EOF'
public enum ImplementedType {
    case original
}
EOF

cat >"$root/Markdown EditorTests/FixtureTests.swift" <<'EOF'
import Testing
@testable import Fixture

@Test func fixtureProof() {
    #expect(fixtureValue() == 1)
}
EOF

cat >"$root/docs/REQUIREMENTS.md" <<'EOF'
| REQ-001 | Fixture requirement | COR-61 | Done | `ImplementedType` | test fixtureProof |
EOF
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

cat >"$root/Markdown Editor/Fixture.swift" <<'EOF'
public func fixtureValue() -> Int {
    // return .bounded(range: changed)
    // return .bounded(range: changed)
    return 1
}
EOF
write_manifest 'return .bounded(range: changed)' 'return .full(range: changed)' fixtureProof
expect_failure 'find matches twice' 'find must match exactly once' "$gate" --all --fixture-root "$root"
cat >"$root/Markdown Editor/Fixture.swift" <<'EOF'
public func fixtureValue() -> Int {
    // return .bounded(range: changed)
    return 1
}
EOF

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

cat >"$root/ScriptsPolicy.swift" <<'EOF'
policy
EOF
write_manifest 'return .bounded(range: changed)' 'return .full(range: changed)' fixtureProof Scripts/ScriptsPolicy.swift
expect_failure 'script mutation without explicit policy kind' 'production mutation must target a file outside tests, scripts, and docs' "$gate" --all --fixture-root "$root"

cat >>"$root/docs/REQUIREMENTS.md" <<'EOF'
| REQ-002 | Unmanifested requirement | COR-61 | Done | Markdown Editor/Fixture.swift | test fixtureProof |
EOF
write_manifest 'return .bounded(range: changed)' 'return .full(range: changed)' fixtureProof
expect_failure 'unmanifested Done requirement' 'Done requirement has no falsification manifest' "$gate" --all --fixture-root "$root"

sed -i '' '/| REQ-002 /d' "$root/docs/REQUIREMENTS.md"
write_manifest 'return 1' 'return 2' fixtureProof
"$gate" --all --fixture-root "$root" >/dev/null

# A pending correction manifest must execute without requiring a premature Done claim.
sed -i '' 's/| Done |/| Correction |/' "$root/docs/REQUIREMENTS.md"
"$gate" --all --fixture-root "$root" >/dev/null
sed -i '' 's/| Correction |/| Done |/' "$root/docs/REQUIREMENTS.md"

write_manifest 'return 1' 'return .notACompileableValue' fixtureProof
expect_failure 'noncompiling mutant' 'mutant does not compile' "$gate" --all --fixture-root "$root"

write_manifest 'return 1' 'return 1' fixtureProof
expect_failure 'all-green mutant' 'all expect_red proofs remained green' "$gate" --all --fixture-root "$root"

write_manifest 'return 1' 'return 2' fixtureProof
"$gate" --all --fixture-root "$root" >/dev/null
rg -q 'return 1' "$root/Markdown Editor/Fixture.swift" || {
    echo "test-check-falsification: isolated mutation modified the fixture source" >&2
    exit 1
}

# Cross-mutation isolation inside one reused slot.
#
# A slot is warm and sequential: it runs several manifests back to back against the same checkout
# and the same DerivedData. Staleness in that arrangement fails closed — a mutation that does not
# take effect leaves its proof green, and 'all expect_red proofs remained green' is already a
# failure. The dangerous direction is the opposite one, and it is the reason this fixture exists:
# a proof going red because of the *previous* mutation in the same slot would be reported as this
# manifest's PASS, which is a tautological proof wearing a gate's uniform.
#
# REQ-001 mutates Fixture.swift so that fixtureProof genuinely goes red. REQ-002 then runs in the
# same slot, mutates a different file harmlessly, and names fixtureProof as its own expect_red.
# By then fixtureProof must be green again, so the gate must FAIL. If REQ-001's mutation survived
# into REQ-002 — through a missed restore or a reused build artifact — fixtureProof would still be
# red and REQ-002 would be credited with a discrimination it never made.
cat >"$root/Markdown Editor/Neighbour.swift" <<'EOF'
public func neighbourValue() -> Int {
    return 10
}
EOF
cat >>"$root/Markdown EditorTests/FixtureTests.swift" <<'EOF'

@Test func neighbourProof() {
    #expect(neighbourValue() >= 0)
}
EOF
cat >>"$root/docs/REQUIREMENTS.md" <<'EOF'
| REQ-002 | Neighbour requirement | COR-61 | Done | `neighbourValue` | test neighbourProof |
EOF
write_manifest 'return 1' 'return 2' fixtureProof
jq -n '{requirement:"REQ-002",mutations:[{rationale:"The neighbour must not borrow another mutation.",file:"Markdown Editor/Neighbour.swift",find:"return 10",replace:"return 11",expect_red:["fixtureProof"]}]}' \
    >"$root/Falsification/REQ-002.json"
FALSIFICATION_WORKERS=1 \
    expect_failure 'cross-mutation contamination in a reused slot' 'all expect_red proofs remained green' \
    env FALSIFICATION_WORKERS=1 "$gate" --all --fixture-root "$root"
rm -f "$root/Falsification/REQ-002.json"
sed -i '' '/| REQ-002 /d' "$root/docs/REQUIREMENTS.md"

write_manifest 'return 1' 'return 2' missingProof
expect_failure 'unmatched expected proof' 'did not pass on the exact preimage' "$gate" --all --fixture-root "$root"

# Restore a valid entry before the changed-range rehearsal. The preceding case is intentionally
# invalid and must not contaminate the fixture's later baseline commit.
write_manifest 'return 1' 'return 2' fixtureProof

git -C "$root" init -q
git -C "$root" config user.email test@example.invalid
git -C "$root" config user.name falsification-test
git -C "$root" add .
git -C "$root" commit -qm baseline
base="$(git -C "$root" rev-parse HEAD)"
jq '.mutations[0].rationale = "The changed-range fixture selects this manifest."' \
    "$root/Falsification/REQ-001.json" >"$root/Falsification/REQ-001.json.tmp"
mv "$root/Falsification/REQ-001.json.tmp" "$root/Falsification/REQ-001.json"
git -C "$root" add Falsification/REQ-001.json
git -C "$root" commit -qm "change falsification manifest"
sed -i '' 's/case original/case changed/' "$root/Markdown Editor/Implemented.swift"
git -C "$root" add 'Markdown Editor/Implemented.swift'
git -C "$root" commit -qm "change implemented source"
"$gate" --changed "$base..HEAD" --fixture-root "$root" >/dev/null

echo "test-check-falsification: PASS (schema, execution, isolation, and changed-selection fixtures observed)"
