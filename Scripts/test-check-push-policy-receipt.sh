#!/bin/bash
# REQ-134: a stale receipt must be refused by the real push-policy route.
set -euo pipefail

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
fixture="$root/repo"
mkdir -p "$fixture/Scripts"
cp "$(dirname "$0")/check-push-policy.sh" "$fixture/Scripts/check-push-policy.sh"
chmod +x "$fixture/Scripts/check-push-policy.sh"
printf '.gate-receipt.json\nScripts/check-push-policy.sh\n' > "$fixture/.gitignore"
git -C "$fixture" init -q
git -C "$fixture" config user.email test@example.invalid
git -C "$fixture" config user.name receipt-test
git -C "$fixture" add .gitignore
printf 'base\n' > "$fixture/README.md"
git -C "$fixture" add README.md
git -C "$fixture" commit -qm base
base="$(git -C "$fixture" rev-parse HEAD)"
printf 'head\n' >> "$fixture/README.md"
git -C "$fixture" add README.md
git -C "$fixture" commit -qm head
head="$(git -C "$fixture" rev-parse HEAD)"
tree="$(git -C "$fixture" rev-parse "$base^{tree}")"
jq -n --arg head "$base" --arg tree "$tree" \
    '{head:$head,tree:$tree,scope:"full",result:"pass",gates:{"documentation-authority":"pass", "instrumentation-coverage":"pass", tests:"pass", "proof-results":"pass", "delivery-status":"pass", falsification:"pass"}}' \
    > "$fixture/.gate-receipt.json"

if (cd "$fixture" && ./Scripts/check-push-policy.sh --remote-ref refs/heads/main --range "$base..$head") >/dev/null 2>&1; then
    echo "REQ-134 proof failed: stale receipt was accepted" >&2
    exit 1
fi
echo "REQ-134 proof PASS: stale receipt refused"
