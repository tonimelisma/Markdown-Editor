#!/bin/bash
# COR-57: enable the tracked hook for this clone/worktree.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/Scripts/hooks/pre-push"
test -x "$hook" || { echo "install-hooks: pre-push is missing or not executable" >&2; exit 1; }
git -C "$repo_root" config extensions.worktreeConfig true
git -C "$repo_root" config --worktree core.hooksPath Scripts/hooks
actual="$(git -C "$repo_root" config --worktree --get core.hooksPath)"
[[ "$actual" == Scripts/hooks ]] || { echo "install-hooks: core.hooksPath is '$actual'" >&2; exit 1; }
echo "install-hooks: enabled tracked hooks at $actual"
echo "install-hooks: --no-verify can bypass this local policy; server-side protection remains unavailable on the current GitHub plan"
