#!/bin/bash
# REQ-138: the falsification gate must reject an all-green mutation.
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
    name: "FalsificationRedGateFixture",
    products: [.library(name: "Fixture", targets: ["Fixture"])],
    targets: [
        .target(name: "Fixture", path: "Markdown Editor"),
        .testTarget(name: "FixtureTests", dependencies: ["Fixture"], path: "Markdown EditorTests"),
    ]
)
EOF

cat >"$root/Markdown Editor/Fixture.swift" <<'EOF'
public func fixtureValue() -> Int {
    return 1
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
| REQ-001 | Fixture requirement | COR-61 | Done | `fixtureValue` | test fixtureProof |
EOF

jq -n \
    '{requirement:"REQ-001",mutations:[{rationale:"An unchanged production preimage must be rejected as all-green.",file:"Markdown Editor/Fixture.swift",find:"return 1",replace:"return 1",expect_red:["fixtureProof"]}]}' \
    >"$root/Falsification/REQ-001.json"

output="$("$gate" --all --fixture-root "$root" 2>&1 || true)"
if [[ "$output" != *"all expect_red proofs remained green"* ]]; then
    echo "test-check-falsification-red-gate: gate did not reject the all-green fixture" >&2
    echo "$output" >&2
    exit 1
fi

echo "test-check-falsification-red-gate: PASS (all-green mutation rejected)"
