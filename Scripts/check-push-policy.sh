#!/bin/bash
# COR-57 / REQ-133/134: the single owner of the local push policy.
set -euo pipefail

usage() {
    echo "usage: check-push-policy.sh --remote-ref <ref> --range <base>..<head>" >&2
    exit 2
}

remote_ref=""
range=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remote-ref) [[ $# -ge 2 ]] || usage; remote_ref="$2"; shift 2 ;;
        --range) [[ $# -ge 2 ]] || usage; range="$2"; shift 2 ;;
        *) usage ;;
    esac
done
[[ -n "$remote_ref" && -n "$range" ]] || usage
[[ "$range" == *..* && "$range" != *...* ]] || { echo "push-policy: invalid range '$range'" >&2; exit 1; }

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "push-policy: not a git repository" >&2; exit 1; }
base="${range%%..*}"
head="${range##*..}"
[[ -n "$base" && -n "$head" ]] || { echo "push-policy: invalid range '$range'" >&2; exit 1; }
git rev-parse --verify "$base^{commit}" >/dev/null 2>&1 || { echo "push-policy: base is not a commit: $base" >&2; exit 1; }
git rev-parse --verify "$head^{commit}" >/dev/null 2>&1 || { echo "push-policy: head is not a commit: $head" >&2; exit 1; }

# A receipt is meaningful only for the committed tree that was tested.  Refuse a push while
# tracked or unexpected untracked work is present, rather than allowing a receipt for HEAD to
# certify a different checkout.  The ignored receipt and ignored build artefacts are intentional.
if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
    echo "push-policy: REFUSED — worktree is not clean; receipt cannot be bound to the tested tree" >&2
    exit 1
fi
tree="$(git rev-parse "$head^{tree}")"

if [[ "$remote_ref" == refs/heads/main ]]; then
    offending_commit=""
    offending_path=""
    while IFS= read -r commit; do
        while IFS= read -r path; do
            case "$path" in
                "Markdown Editor/"*.swift|"Markdown EditorTests/"*.swift)
                    offending_commit="$commit"
                    offending_path="$path"
                    break 2
                    ;;
            esac
        done < <(git diff-tree --root --no-commit-id --name-only -r "$commit")
    done < <(git rev-list "$range")
    if [[ -n "$offending_commit" ]]; then
        summary="$(git show -s --format='%h %s' "$offending_commit")"
        echo "push-policy: REFUSED — Swift source would be pushed to refs/heads/main" >&2
        echo "push-policy: offending commit: $summary" >&2
        echo "push-policy: offending path: $offending_path" >&2
        exit 1
    fi
fi

receipt="$repo_root/.gate-receipt.json"
[[ -r "$receipt" ]] || { echo "push-policy: REFUSED — missing $receipt" >&2; exit 1; }

# A push to main normally needs a full-scope receipt (the complete test suite and performance
# corpus). A range whose diff touches nothing but prose documentation, and that introduces no new
# "Done"/"✅" delivery claim, makes no assertion a build or test could contradict — CLAUDE.md §5
# already describes docs-only changes as committing "directly to main; no branch, worktree, or
# PR", and a full xcodebuild+test run for a plan-writing change is exactly the mismatch that
# claim describes. The Done/✅ scan is deliberately broad (the bare word "Done" anywhere newly
# added to either status file, not just inside a table cell) because a false positive here only
# costs an unnecessary full run, while a false negative would let a delivery claim reach main
# without the run that REQ-136/COR-59 exists to require.
is_pure_docs_range() {
    local scan_range="$1" commit path
    while IFS= read -r commit; do
        while IFS= read -r path; do
            case "$path" in
                docs/*.md|CLAUDE.md|AGENTS.md|.markdownlint-cli2.jsonc) ;;
                *) return 1 ;;
            esac
        done < <(git diff-tree --root --no-commit-id --name-only -r "$commit")
    done < <(git rev-list "$scan_range")
    if git diff "$scan_range" -- docs/REQUIREMENTS.md docs/ROADMAP.md 2>/dev/null \
        | grep -qE '^\+.*(✅|Done)'; then
        return 1
    fi
    return 0
}

required_scope=fast
if [[ "$remote_ref" == refs/heads/main ]]; then
    required_scope=full
    is_pure_docs_range "$range" && required_scope=fast
fi

jq -e \
    --arg head "$head" \
    --arg tree "$tree" \
    --arg required_scope "$required_scope" \
    'type == "object" and .head == $head and .tree == $tree and .result == "pass" and
     (.gates | type == "object") and
     (.gates | has("documentation-authority") and has("instrumentation-coverage") and
               has("tests") and has("proof-results") and has("delivery-status")) and
     (.gates | ([to_entries[] | select(.key != "delivery-status") | .value] | length == 4 and all(. == "pass"))) and
     (
       (.scope == "full" and .gates["delivery-status"] == "pass") or
       ($required_scope == "fast" and .scope == "fast" and .gates["delivery-status"] == "structural")
     )' \
    "$receipt" >/dev/null 2>&1 || {
        echo "push-policy: REFUSED — receipt does not prove a passing $required_scope run at $head" >&2
        exit 1
    }

echo "push-policy: PASS — $remote_ref at $head has a passing $required_scope receipt"
