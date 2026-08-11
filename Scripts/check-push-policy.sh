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
required_scope=fast
[[ "$remote_ref" == refs/heads/main ]] && required_scope=full

jq -e \
    --arg head "$head" \
    --arg tree "$tree" \
    --arg required_scope "$required_scope" \
    'type == "object" and .head == $head and .tree == $tree and .result == "pass" and
     ((.scope == "fast") or (.scope == "full")) and
     (($required_scope == "fast") or (.scope == "full")) and
     (.gates | type == "object") and
     (.gates | has("documentation-authority") and has("instrumentation-coverage") and
               has("tests") and has("proof-results")) and
     (.gates | [.[]] | length == 4 and all(.[]; . == "pass"))' \
    "$receipt" >/dev/null 2>&1 || {
        echo "push-policy: REFUSED — receipt does not prove a passing $required_scope run at $head" >&2
        exit 1
    }

echo "push-policy: PASS — $remote_ref at $head has a passing $required_scope receipt"
