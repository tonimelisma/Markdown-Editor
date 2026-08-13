#!/bin/bash
# COR-68: proof-result fixtures distinguish observed execution from cited source text.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
gate="$repo_root/Scripts/check-proof-results.sh"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/docs" "$root/Markdown Editor" "$root/Markdown EditorTests" "$root/bin" "$root/results.xcresult"

cat > "$root/docs/REQUIREMENTS.md" <<'EOF'
| REQ-001 | fixture | COR-68 | Done | FixtureOwner | `passing` |
EOF
cat > "$root/Markdown Editor/Fixture.swift" <<'EOF'
struct FixtureOwner {}
EOF
cat > "$root/Markdown EditorTests/FixtureTests.swift" <<'EOF'
@Test func passing() {}
@Test func omitted() {}
EOF
cat > "$root/bin/xcrun" <<'EOF'
#!/bin/bash
cat "$FIXTURE_XCRESULT_JSON"
EOF
chmod +x "$root/bin/xcrun"
cat > "$root/passing.json" <<'EOF'
{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"FixtureTests/passing()","result":"Passed"}]}
EOF
FIXTURE_XCRESULT_JSON="$root/passing.json" PATH="$root/bin:$PATH" \
    "$gate" "$root/results.xcresult" --fixture-root "$root" >/dev/null

cat > "$root/docs/REQUIREMENTS.md" <<'EOF'
| REQ-001 | fixture | COR-68 | Done | FixtureOwner | `omitted` |
EOF
if FIXTURE_XCRESULT_JSON="$root/passing.json" PATH="$root/bin:$PATH" \
    "$gate" "$root/results.xcresult" --fixture-root "$root" >/dev/null 2>&1; then
    echo "test-check-proof-results: omitted cited proof unexpectedly passed" >&2
    exit 1
fi

cat > "$root/docs/REQUIREMENTS.md" <<'EOF'
| REQ-001 | fixture | COR-68 | Done | FixtureOwner | `passing` |
EOF
cat > "$root/Markdown EditorTests/FixtureTests.swift" <<'EOF'
@Test func passing() {}
@Test func unmapped() {}
EOF
cat > "$root/unmapped.json" <<'EOF'
{"testNodes":[
  {"nodeType":"Test Case","nodeIdentifier":"FixtureTests/passing()","result":"Passed"},
  {"nodeType":"Test Case","nodeIdentifier":"FixtureTests/unmapped()","result":"Passed"}
]}
EOF
if FIXTURE_XCRESULT_JSON="$root/unmapped.json" PATH="$root/bin:$PATH" \
    "$gate" "$root/results.xcresult" --fixture-root "$root" >/dev/null 2>&1; then
    echo "test-check-proof-results: unmapped failing test unexpectedly passed" >&2
    exit 1
fi

echo "test-check-proof-results: PASS (execution and mapping fixtures observed)"
