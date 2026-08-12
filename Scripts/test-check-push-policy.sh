#!/bin/bash
# COR-57 / REQ-133/134: fixture tests for branch and receipt policy.
set -euo pipefail

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
fixture="$root/repo"
policy_source="$(dirname "$0")/check-push-policy.sh"
mkdir -p "$fixture/Scripts/hooks"
cp "$(dirname "$0")/check-push-policy.sh" "$fixture/Scripts/check-push-policy.sh"
cp "$(dirname "$0")/write-gate-receipt.sh" "$fixture/Scripts/write-gate-receipt.sh"
cp "$(dirname "$0")/install-hooks.sh" "$fixture/Scripts/install-hooks.sh"
cp "$(dirname "$0")/hooks/pre-push" "$fixture/Scripts/hooks/pre-push"
chmod +x "$fixture/Scripts/check-push-policy.sh"
chmod +x "$fixture/Scripts/write-gate-receipt.sh" "$fixture/Scripts/install-hooks.sh" "$fixture/Scripts/hooks/pre-push"
git -C "$fixture" init -q
git -C "$fixture" config user.email test@example.invalid
git -C "$fixture" config user.name policy-test
mkdir -p "$fixture/docs" "$fixture/Markdown Editor"
printf '.gate-receipt.json\n' > "$fixture/.gitignore"
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

printf '| REQ-900 | x | y | Done | z | w |\n' >> "$fixture/docs/REQUIREMENTS.md"
git -C "$fixture" add .
git -C "$fixture" commit -qm "docs claiming Done"
docs_done_head="$(git -C "$fixture" rev-parse HEAD)"

mkdir -p "$fixture/Scripts"
printf '#!/bin/bash\n' > "$fixture/Scripts/unrelated.sh"
git -C "$fixture" add .
git -C "$fixture" commit -qm "docs plus a script"
docs_plus_script_head="$(git -C "$fixture" rev-parse HEAD)"

write_receipt() {
    local head="$1" scope="$2" result="$3" delivery="${4:-pass}"
    local tree
    tree="$(git -C "$fixture" rev-parse "$head^{tree}")"
    jq -n --arg head "$head" --arg tree "$tree" --arg scope "$scope" --arg result "$result" --arg delivery "$delivery" \
        '{head:$head,tree:$tree,scope:$scope,result:$result,gates:{"documentation-authority":"pass","instrumentation-coverage":"pass",tests:"pass","proof-results":"pass","delivery-status":$delivery,falsification:"pass"}}' \
        > "$fixture/.gate-receipt.json"
}
expect_refused() { if (cd "$fixture" && "$fixture/Scripts/check-push-policy.sh" "$@") 2>/dev/null; then echo "expected refusal: $*" >&2; exit 1; fi; }
expect_allowed() { (cd "$fixture" && "$fixture/Scripts/check-push-policy.sh" "$@") >/dev/null; }

expect_refused --remote-ref refs/heads/main --range "$base..$swift_head"
diagnostic="$(cd "$fixture" && "$fixture/Scripts/check-push-policy.sh" --remote-ref refs/heads/main --range "$base..$swift_head" 2>&1 || true)"
[[ "$diagnostic" == *"offending commit:"* && "$diagnostic" == *"${swift_head:0:7}"* ]] || {
    echo "expected offending commit in refusal diagnostic" >&2
    exit 1
}
write_receipt "$docs_head" full pass
expect_allowed --remote-ref refs/heads/main --range "$swift_head..$docs_head"

# REQ-134 addendum: a pure-docs range to main may satisfy the policy with a fast-scope receipt
# (structural delivery), since it makes no claim a build or test run could contradict.
write_receipt "$docs_head" fast pass structural
expect_allowed --remote-ref refs/heads/main --range "$swift_head..$docs_head"

# A docs-only range that adds a "Done" delivery claim still requires full scope — a fast receipt
# is refused even though every changed path is under docs/.
write_receipt "$docs_done_head" fast pass structural
expect_refused --remote-ref refs/heads/main --range "$docs_head..$docs_done_head"
write_receipt "$docs_done_head" full pass
expect_allowed --remote-ref refs/heads/main --range "$docs_head..$docs_done_head"

# A range that touches docs plus one non-docs file (here a Scripts/*.sh addition) still requires
# full scope — the pure-docs exception does not extend to tooling/scripts.
write_receipt "$docs_plus_script_head" fast pass structural
expect_refused --remote-ref refs/heads/main --range "$docs_done_head..$docs_plus_script_head"
write_receipt "$docs_plus_script_head" full pass
expect_allowed --remote-ref refs/heads/main --range "$docs_done_head..$docs_plus_script_head"

write_receipt "$swift_head" fast pass
expect_refused --remote-ref refs/heads/cor-99-x --range "$base..$swift_head"
write_receipt "$swift_head" fast pass structural
expect_allowed --remote-ref refs/heads/cor-99-x --range "$base..$swift_head"
write_receipt "$swift_head" fast pass
expect_refused --remote-ref refs/heads/cor-99-x --range "$base..$swift_head"
write_receipt "$base" full pass
expect_refused --remote-ref refs/heads/cor-99-x --range "$base..$swift_head"
write_receipt "$swift_head" fast fail
expect_refused --remote-ref refs/heads/cor-99-x --range "$base..$swift_head"
rm "$fixture/.gate-receipt.json"
expect_refused --remote-ref refs/heads/cor-99-x --range "$base..$swift_head"

# Exercise both the tracked hook and the worktree-safe installer, including first pushes and
# deletion refs. These are deliberately process-level checks: no UI is driven or inspected.
(cd "$fixture" && ./Scripts/install-hooks.sh >/dev/null)
[[ "$(git -C "$fixture" config --worktree --get core.hooksPath)" == "Scripts/hooks" ]] || {
    echo "installer did not set the worktree-local hook path" >&2
    exit 1
}
linked="$root/linked"
git -C "$fixture" worktree add -q -b linked "$linked" "$base"
(cd "$linked" && ./Scripts/install-hooks.sh >/dev/null)
[[ "$(git -C "$linked" config --worktree --get core.hooksPath)" == "Scripts/hooks" ]] || {
    echo "linked-worktree installer did not set a local hook path" >&2
    exit 1
}
write_receipt "$swift_head" fast pass structural
zero="0000000000000000000000000000000000000000"
printf 'refs/heads/cor-99-x %s refs/heads/cor-99-x %s\n' "$swift_head" "$zero" |
    (cd "$fixture" && ./Scripts/hooks/pre-push)
if printf 'refs/heads/main %s refs/heads/main %s\n' "$swift_head" "$zero" |
    (cd "$fixture" && ./Scripts/hooks/pre-push) >/dev/null 2>&1; then
    echo "first-push main Swift change was not refused" >&2
    exit 1
fi
printf 'refs/heads/cor-99-x %s refs/heads/cor-99-x %s\n' "$zero" "$swift_head" |
    (cd "$fixture" && ./Scripts/hooks/pre-push)

# Recorded falsifying mutations: each mutation makes the corresponding cited proof go green on
# a defective policy, and this fixture therefore turns red if the proof stops discriminating.
mutated_branch="$root/mutated-branch-policy.sh"
sed 's|"Markdown Editor/"\*\.swift|"NEVER_MATCH"|g' "$policy_source" > "$mutated_branch"
chmod +x "$mutated_branch"
write_receipt "$swift_head" full pass
if (cd "$fixture" && "$mutated_branch" --remote-ref refs/heads/main --range "$base..$swift_head") >/dev/null 2>&1; then
    echo "falsifying mutation REQ-133: PASS (the mutated policy made the refusal proof go green)"
else
    echo "falsifying mutation REQ-133: FAIL" >&2
    exit 1
fi

mutated_receipt="$root/mutated-receipt-policy.sh"
sed -e 's|\.head == \$head|true|g' -e 's|\.tree == \$tree|true|g' "$policy_source" > "$mutated_receipt"
chmod +x "$mutated_receipt"
write_receipt "$base" fast pass structural
if (cd "$fixture" && "$mutated_receipt" --remote-ref refs/heads/cor-99-x --range "$base..$swift_head") >/dev/null 2>&1; then
    echo "falsifying mutation REQ-134: PASS (the mutated policy made the stale-receipt proof go green)"
else
    echo "falsifying mutation REQ-134: FAIL" >&2
    exit 1
fi

# Falsifying mutation for the pure-docs fast-scope exception: force is_pure_docs_range to always
# succeed, and confirm the docs-plus-Done fixture (which real REQUIREMENTS.md content newly
# claiming Done must still require full scope) goes green on the defective policy.
mutated_docs_check="$root/mutated-docs-check-policy.sh"
sed 's|^    return 0$|    return 0 # ALWAYS|; s|return 1$|return 0|g' "$policy_source" > "$mutated_docs_check"
chmod +x "$mutated_docs_check"
write_receipt "$docs_done_head" fast pass structural
if (cd "$fixture" && "$mutated_docs_check" --remote-ref refs/heads/main --range "$docs_head..$docs_done_head") >/dev/null 2>&1; then
    echo "falsifying mutation REQ-134-docs: PASS (the mutated policy made the Done-claim fast-scope proof go green)"
else
    echo "falsifying mutation REQ-134-docs: FAIL" >&2
    exit 1
fi
echo "check-push-policy fixtures: PASS"
