#!/bin/bash
# COR-57 / REQ-133/134: fixture tests for branch and receipt policy.
set -euo pipefail

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
fixture="$root/repo"
mkdir -p "$fixture/Scripts"
cp "$(dirname "$0")/check-push-policy.sh" "$fixture/Scripts/check-push-policy.sh"
chmod +x "$fixture/Scripts/check-push-policy.sh"
git -C "$fixture" init -q
git -C "$fixture" config user.email test@example.invalid
git -C "$fixture" config user.name policy-test
mkdir -p "$fixture/docs" "$fixture/Markdown Editor"
printf 'base\n' > "$fixture/docs/README.md"
git -C "$fixture" add .
git -C "$fixture" commit -qm base
base="$(git -C "$fixture" rev-parse HEAD)"

printf 'swift\n' > "$fixture/Markdown Editor/Fixture.swift"
git -C "$fixture" add .
git -C "$fixture" commit -qm swift
swift_head="$(git -C "$fixture" rev-parse HEAD)"

printf 'docs\n' >> "$fixture/docs/README.md"
git -C "$fixture" add .
git -C "$fixture" commit -qm docs
docs_head="$(git -C "$fixture" rev-parse HEAD)"

write_receipt() {
    local head="$1" scope="$2" result="$3"
    jq -n --arg head "$head" --arg scope "$scope" --arg result "$result" \
        '{head:$head,scope:$scope,result:$result,gates:{"documentation-authority":"pass","instrumentation-coverage":"pass",tests:"pass","proof-results":"pass"}}' \
        > "$fixture/.gate-receipt.json"
}
expect_refused() { if (cd "$fixture" && "$fixture/Scripts/check-push-policy.sh" "$@") 2>/dev/null; then echo "expected refusal: $*" >&2; exit 1; fi; }
expect_allowed() { (cd "$fixture" && "$fixture/Scripts/check-push-policy.sh" "$@") >/dev/null; }

expect_refused --remote-ref refs/heads/main --range "$base..$swift_head"
write_receipt "$docs_head" full pass
expect_allowed --remote-ref refs/heads/main --range "$swift_head..$docs_head"
write_receipt "$swift_head" fast pass
expect_allowed --remote-ref refs/heads/cor-99-x --range "$base..$swift_head"
write_receipt "$swift_head" fast pass
expect_refused --remote-ref refs/heads/main --range "$base..$swift_head"
write_receipt "$base" full pass
expect_refused --remote-ref refs/heads/cor-99-x --range "$base..$swift_head"
write_receipt "$swift_head" fast fail
expect_refused --remote-ref refs/heads/cor-99-x --range "$base..$swift_head"
rm "$fixture/.gate-receipt.json"
expect_refused --remote-ref refs/heads/cor-99-x --range "$base..$swift_head"
echo "check-push-policy fixtures: PASS"
