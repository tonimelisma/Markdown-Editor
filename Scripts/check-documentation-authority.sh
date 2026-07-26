#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

failures=0
check_temp_dir="$(mktemp -d)"
trap 'rm -r -- "$check_temp_dir"' EXIT

fail() {
    printf 'documentation-authority: %s\n' "$1" >&2
    failures=$((failures + 1))
}

for required in \
    docs/VISION.md \
    docs/ENGINEERING.md \
    docs/REQUIREMENTS.md \
    docs/ROADMAP.md \
    docs/research/README.md \
    docs/plans/README.md \
    .markdownlint-cli2.jsonc
do
    [[ -f "$required" ]] || fail "missing required current document: $required"
done

if [[ -d docs/decisions ]] && find docs/decisions -type f -print -quit | grep -q .; then
    fail "docs/decisions is forbidden; current architecture belongs in ENGINEERING.md"
fi

forbidden_report="$check_temp_dir/forbidden.txt"
if rg -n 'ADR-[0-9]{4}|PLAN-[0-9]{4}|RESEARCH-[0-9]{4}|docs/decisions' \
    CLAUDE.md docs >"$forbidden_report"
then
    cat "$forbidden_report" >&2
    fail "historical decision/numbered-plan/numbered-research references remain"
fi

for plan in docs/plans/*.md; do
    [[ "$(basename "$plan")" == "README.md" ]] && continue
    if ! rg -q '^- \*\*Status:\*\* Approved; not implemented$' "$plan"; then
        fail "plan must be approved and unimplemented: $plan"
    fi
    plan_name="$(basename "$plan")"
    rg -Fq "(plans/$plan_name)" docs/ROADMAP.md \
        || fail "approved plan is not linked from ROADMAP: $plan"
done

for research in docs/research/*.md; do
    [[ "$(basename "$research")" == "README.md" ]] && continue
    rg -q '^- \*\*Authority:\*\* Evidence only' "$research" \
        || fail "research lacks evidence-only authority: $research"
    rg -q '^- \*\*First researched:\*\* ' "$research" \
        || fail "research lacks first-researched date: $research"
    rg -q '^- \*\*Last verified:\*\* ' "$research" \
        || fail "research lacks last-verified date: $research"
    rg -q '^- \*\*Refresh when:\*\* ' "$research" \
        || fail "research lacks refresh trigger: $research"
    research_name="$(basename "$research")"
    rg -Fq "($research_name)" docs/research/README.md \
        || fail "research is not indexed in docs/research/README.md: $research"
done

while IFS=$'\t' read -r source target; do
    case "$target" in
        http://*|https://*|mailto:*|\#*) continue ;;
    esac
    path="${target%%#*}"
    [[ -z "$path" ]] && continue
    if [[ "$path" = /* ]]; then
        resolved="$path"
    else
        resolved="$(dirname "$source")/$path"
    fi
    [[ -e "$resolved" ]] || fail "broken local link in $source: $target"
done < <(
    perl -ne 'while (/\[[^]]+\]\(([^)]+)\)/g) { print "$ARGV\t$1\n" }' \
        CLAUDE.md docs/*.md docs/plans/*.md docs/research/*.md
)

requirements="$check_temp_dir/requirements.txt"
anchors="$check_temp_dir/anchors.txt"

rg --no-filename -o 'REQ-[0-9]{3}' docs/REQUIREMENTS.md | sort -u >"$requirements"
rg --no-filename -o 'REQ-[0-9]{3}' 'Markdown Editor' 'Markdown EditorTests' | sort -u >"$anchors"

while IFS= read -r anchor; do
    rg -qx "$anchor" "$requirements" || fail "code/test anchor has no requirement: $anchor"
done <"$anchors"

done_report="$check_temp_dir/incomplete-done.txt"
if ! awk -F'|' '
    $0 ~ /^\| REQ-[0-9][0-9][0-9] / && $5 ~ / Done / {
        id=$2; implementation=$6; verification=$7
        gsub(/^ +| +$/, "", id)
        gsub(/^ +| +$/, "", implementation)
        gsub(/^ +| +$/, "", verification)
        incomplete=(implementation == "" || implementation == "—" || verification == "" || verification == "—" || verification ~ / pending/)
        if (incomplete) print id
    }
' docs/REQUIREMENTS.md >"$done_report"
then
    fail "could not parse Done requirement rows"
else
    while IFS= read -r incomplete_done; do
        [[ -z "$incomplete_done" ]] && continue
        fail "Done requirement lacks current implementation or verification: $incomplete_done"
    done <"$done_report"
fi

if [[ ! -L AGENTS.md ]] || [[ "$(readlink AGENTS.md)" != "CLAUDE.md" ]]; then
    fail "AGENTS.md must remain a symlink to CLAUDE.md"
fi

if find . -maxdepth 3 \( -iname '*UITest*' -o -iname '*XCUITest*' \) -print -quit | grep -q .; then
    fail "UI-test files or directories are forbidden"
fi

if (( failures > 0 )); then
    printf 'documentation-authority: FAILED (%d issue%s)\n' \
        "$failures" "$([[ $failures -eq 1 ]] && printf '' || printf 's')" >&2
    exit 1
fi

printf 'documentation-authority: PASS\n'
