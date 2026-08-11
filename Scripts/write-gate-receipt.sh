#!/bin/bash
# COR-57: write the one machine-readable receipt consumed by the pre-push policy.
set -euo pipefail

if [[ $# -ne 6 ]]; then
    echo "usage: write-gate-receipt.sh <fast|full> <pass|fail> <doc> <instrumentation> <tests> <proof>" >&2
    exit 2
fi

scope="$1"
result="$2"
doc="$3"
instrumentation="$4"
tests="$5"
proof="$6"
case "$scope:$result:$doc:$instrumentation:$tests:$proof" in
    fast:pass:pass:pass:pass:pass|fast:fail:pass:pass:pass:pass|fast:fail:*|full:pass:pass:pass:pass:pass|full:fail:pass:pass:pass:pass|full:fail:*) ;;
    *) echo "write-gate-receipt: invalid receipt values" >&2; exit 2 ;;
esac

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
if ! git -C "$repo_root" diff --quiet || ! git -C "$repo_root" diff --cached --quiet || [[ -n "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ]]; then
    echo "write-gate-receipt: refusing to certify a dirty worktree" >&2
    exit 1
fi
head="$(git -C "$repo_root" rev-parse HEAD)"
tree="$(git -C "$repo_root" rev-parse 'HEAD^{tree}')"
ran="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
tmp="$repo_root/.gate-receipt.json.tmp.$$"
trap 'rm -f "$tmp"' EXIT

jq -n \
    --arg head "$head" \
    --arg tree "$tree" \
    --arg ran "$ran" \
    --arg scope "$scope" \
    --arg result "$result" \
    --arg doc "$doc" \
    --arg instrumentation "$instrumentation" \
    --arg tests "$tests" \
    --arg proof "$proof" \
    '{head:$head, tree:$tree, ran:$ran, scope:$scope, result:$result,
      gates:{"documentation-authority":$doc, "instrumentation-coverage":$instrumentation,
             tests:$tests, "proof-results":$proof}}' > "$tmp"
mv "$tmp" "$repo_root/.gate-receipt.json"
