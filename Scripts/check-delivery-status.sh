#!/bin/bash
# REQ-136: delivery status is derived from declared requirements and observed proof results.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bundle=""
fixture_root=""
fixture_proof_status=""
git_root_override=""
structural_only=0
proof_args=()

usage() {
    cat >&2 <<'USAGE'
usage: check-delivery-status.sh [xcresult-bundle] [--skip-suite NAME]
       check-delivery-status.sh --fixture-root DIR --fixture-proof-status pass|fail
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-suite)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            proof_args+=(--skip-suite "$2")
            shift 2
            ;;
        --fixture-root)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            fixture_root="$2"
            shift 2
            ;;
        --fixture-proof-status)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            fixture_proof_status="$2"
            shift 2
            ;;
        --git-root)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            git_root_override="$2"
            shift 2
            ;;
        --structural-only)
            structural_only=1
            shift
            ;;
        --help)
            usage >&1
            exit 0
            ;;
        --*)
            usage
            exit 2
            ;;
        *)
            [[ -z "$bundle" ]] || { usage; exit 2; }
            bundle="$1"
            shift
            ;;
    esac
done

if [[ -n "$fixture_root" ]]; then
    [[ -n "$fixture_proof_status" ]] || { usage; exit 2; }
    [[ "$fixture_proof_status" == pass || "$fixture_proof_status" == fail ]] || {
        usage
        exit 2
    }
else
    if (( structural_only == 0 )); then
        if [[ -n "$bundle" ]]; then
            ./Scripts/check-proof-results.sh "$bundle" "${proof_args[@]+${proof_args[@]}}"
        else
            ./Scripts/check-proof-results.sh "${proof_args[@]+${proof_args[@]}}"
        fi
    fi
fi

python3 - "$repo_root" "$fixture_root" "$fixture_proof_status" "$git_root_override" "$bundle" <<'PY'
import pathlib
import json
import re
import subprocess
import sys

repo = pathlib.Path(sys.argv[1])
fixture_root = pathlib.Path(sys.argv[2]) if sys.argv[2] else None
fixture_proof_status = sys.argv[3]
git_root_override = pathlib.Path(sys.argv[4]) if sys.argv[4] else None
bundle_path = pathlib.Path(sys.argv[5]) if sys.argv[5] else None
root = fixture_root or repo
git_root = git_root_override or repo
roadmap_path = root / "docs/ROADMAP.md"
requirements_path = root / "docs/REQUIREMENTS.md"
plans_dir = root / "docs/plans"
problems = []

if not roadmap_path.is_file():
    problems.append("missing docs/ROADMAP.md")
if not requirements_path.is_file():
    problems.append("missing docs/REQUIREMENTS.md")
if not plans_dir.is_dir():
    problems.append("missing docs/plans")
if problems:
    for problem in problems:
        print(f"check-delivery-status: {problem}", file=sys.stderr)
    sys.exit(1)

requirement_status = {}
requirements_text = requirements_path.read_text()
for line in requirements_text.splitlines():
    if not line.startswith("| REQ-"):
        continue
    columns = [column.strip() for column in line.split("|")]
    if len(columns) < 6 or not re.fullmatch(r"REQ-\d{3}", columns[1]):
        continue
    requirement_status[columns[1]] = columns[4]
for requirement in re.findall(r"REQ-\d{3}", requirements_text.split("*Reserved by approved", 1)[-1]):
    requirement_status.setdefault(requirement, "Planned")

def parse_delivers(text, label):
    match = re.search(r"(?:^|\()\s*Delivers:\s*([^\)]*)", text, re.IGNORECASE)
    if not match:
        problems.append(f"{label}: missing Delivers field")
        return None
    value = match.group(1).strip()
    if re.search(r"\bnone\b", value, re.IGNORECASE):
        if re.search(r"REQ-\d{3}", value):
            problems.append(f"{label}: Delivers mixes none and requirement IDs")
        return frozenset()
    ids = frozenset(re.findall(r"REQ-\d{3}", value))
    if not ids:
        problems.append(f"{label}: Delivers is neither requirement IDs nor explicit none")
    return ids

def parse_completion_proofs(text, label):
    values = re.findall(r"^\s*Completion-Proofs:\s*(.+)$", text, re.MULTILINE)
    if len(values) != 1:
        problems.append(f"{label}: refactor plan requires exactly one Completion-Proofs field")
        return frozenset()
    proofs = frozenset(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", values[0]))
    if not proofs:
        problems.append(f"{label}: Completion-Proofs must name at least one proof")
    return proofs

plan_delivers = {}
plan_completion = {}
for plan_path in sorted(plans_dir.glob("*.md")):
    if plan_path.name == "README.md":
        continue
    match = re.match(r"(COR|INC|DISC)-\d+", plan_path.name)
    if not match:
        problems.append(f"{plan_path}: filename has no increment ID")
        continue
    increment = re.match(r"((?:COR|INC|DISC)-\d+)", plan_path.name).group(1)
    values = re.findall(r"^- \*\*Delivers:\*\* (.+)$", "\n".join(plan_path.read_text().splitlines()[:12]), re.MULTILINE)
    if len(values) != 1:
        problems.append(f"{plan_path}: expected exactly one Delivers header")
        continue
    parsed = parse_delivers(f"Delivers: {values[0]}", str(plan_path))
    if parsed is not None:
        plan_delivers[increment] = parsed
        if not parsed:
            plan_completion[increment] = parse_completion_proofs(plan_path.read_text(), str(plan_path))

plan_paths = {}
for path in sorted(plans_dir.glob("*.md")):
    if path.name == "README.md":
        continue
    match = re.match(r"((?:COR|INC|DISC)-\d+)-", path.name)
    if match:
        plan_paths.setdefault(match.group(1), []).append(path)

roadmap_rows = []
row_pattern = re.compile(r"^\s*\d+\.\s+(✅|🔵|⚪|🅿️)\s+\*\*((?:COR|INC|DISC)-\d+)\s+—")
roadmap_lines = roadmap_path.read_text().splitlines()
for index, line in enumerate(roadmap_lines):
    match = row_pattern.match(line)
    if not match:
        continue
    status, increment = match.groups()
    block_lines = [line]
    following = index + 1
    while following < len(roadmap_lines) and not row_pattern.match(roadmap_lines[following]):
        block_lines.append(roadmap_lines[following])
        following += 1
    block = "\n".join(block_lines)
    line_number = index + 1
    delivers = parse_delivers(block, f"ROADMAP:{line_number}:{increment}")
    if delivers is not None:
        roadmap_rows.append((line_number, status, increment, delivers, block))

if not roadmap_rows:
    problems.append("ROADMAP contains zero numbered increment rows")

seen = set()
for line_number, status, increment, delivers, block in roadmap_rows:
    if increment in seen:
        problems.append(f"ROADMAP:{line_number}:{increment}: duplicate increment row")
    seen.add(increment)
    plans = plan_paths.get(increment, [])
    if len(plans) > 1:
        problems.append(f"{increment}: multiple plan files: {', '.join(map(str, plans))}")
    declared_plan = plan_delivers.get(increment)

    if status in {"⚪", "🔵"}:
        if not plans:
            problems.append(f"ROADMAP:{line_number}:{increment}: active row has no plan file")
        if declared_plan is not None and declared_plan != delivers:
            problems.append(f"{increment}: ROADMAP Delivers does not match plan Delivers")
        if declared_plan is None and plans:
            problems.append(f"{increment}: plan Delivers could not be resolved")
        if plans and f"(plans/{plans[0].name})" not in block:
            problems.append(f"{increment}: ROADMAP does not link its matching plan {plans[0].name}")
        if declared_plan == frozenset() and increment in plan_completion and not plan_completion[increment]:
            problems.append(f"{increment}: refactor plan has no completion proofs")
        for requirement in sorted(delivers):
            if requirement not in requirement_status:
                problems.append(f"{increment}: Delivers names unknown requirement {requirement}")
            elif requirement_status[requirement] == "Done":
                problems.append(f"{increment}: active row delivers already-Done {requirement}")
    elif status == "✅":
        if plans:
            problems.append(f"ROADMAP:{line_number}:{increment}: delivered row still has a plan file")
        elif not fixture_root or git_root_override:
            head = subprocess.run(["git", "-C", str(git_root), "rev-parse", "HEAD"], capture_output=True, text=True, check=False).stdout.strip()
            base_ref = "HEAD^"
            remote_main = subprocess.run(
                ["git", "-C", str(git_root), "rev-parse", "--verify", "origin/main"],
                capture_output=True, text=True, check=False,
            )
            if remote_main.returncode == 0:
                base_ref = subprocess.run(
                    ["git", "-C", str(git_root), "merge-base", "origin/main", "HEAD"],
                    capture_output=True, text=True, check=False,
                ).stdout.strip() or base_ref
            changed = subprocess.run(
                ["git", "-C", str(git_root), "diff-tree", "--root", "--no-commit-id", "--name-only", "-r", head],
                capture_output=True, text=True, check=False
            ).stdout.splitlines()
            deleted_plans = [p for p in changed if p.startswith(f"docs/plans/{increment}-") and p.endswith(".md")]
            branch_changed = changed
            if base_ref != "HEAD^":
                candidate = f"docs/plans/{increment}-"
                branch_changed = subprocess.run(
                    ["git", "-C", str(git_root), "diff", "--name-only", f"{base_ref}..HEAD"],
                    capture_output=True, text=True, check=False,
                ).stdout.splitlines()
                if not deleted_plans:
                    deleted_plans = [p for p in branch_changed if p.startswith(candidate) and p.endswith(".md")]
            if deleted_plans:
                plan_source_ref = f"{head}^"
                if base_ref not in {"HEAD^", head}:
                    plan_source_ref = base_ref
                original = subprocess.run(
                    ["git", "-C", str(git_root), "show", f"{plan_source_ref}:{deleted_plans[0]}"],
                    capture_output=True, text=True, check=False
                ).stdout
                original_values = re.findall(r"^- \*\*Delivers:\*\* (.+)$", "\n".join(original.splitlines()[:12]), re.MULTILINE)
                if len(original_values) != 1:
                    problems.append(f"{increment}: deleted plan has no single Delivers declaration")
                else:
                    original_delivers = parse_delivers(f"Delivers: {original_values[0]}", f"deleted plan {deleted_plans[0]}")
                    if original_delivers is not None and original_delivers != delivers:
                        problems.append(f"{increment}: ROADMAP Delivers does not match the deleted plan's Delivers")
                    if original_delivers == frozenset():
                        completion = parse_completion_proofs(original, f"deleted plan {deleted_plans[0]}")
                        if not completion:
                            problems.append(f"{increment}: deleted refactor plan has no completion proofs")
                        elif not fixture_root:
                            if bundle_path is None or not bundle_path.is_dir():
                                problems.append(f"{increment}: refactor delivery requires the closing result bundle")
                            else:
                                try:
                                    raw_results = subprocess.run(
                                        ["xcrun", "xcresulttool", "get", "test-results", "tests",
                                         "--path", str(bundle_path), "--format", "json"],
                                        check=True, capture_output=True, text=True,
                                    ).stdout
                                    result_data = json.loads(raw_results)
                                    observed = {}
                                    def walk_results(node):
                                        if isinstance(node, dict):
                                            if node.get("nodeType") == "Test Case":
                                                identifier = node.get("nodeIdentifier") or node.get("name") or ""
                                                leaf = re.sub(r"\(.*\)$", "", identifier.rsplit("/", 1)[-1]).strip()
                                                if leaf:
                                                    observed.setdefault(leaf, set()).add(node.get("result") or "")
                                            for value in node.values():
                                                walk_results(value)
                                        elif isinstance(node, list):
                                            for value in node:
                                                walk_results(value)
                                    walk_results(result_data)
                                    for proof in sorted(completion):
                                        if proof not in observed or not observed[proof].issubset({"Passed", "Expected Failure"}):
                                            problems.append(f"{increment}: completion proof `{proof}` was not observed passing in the closing result bundle")
                                except (subprocess.CalledProcessError, OSError, ValueError) as error:
                                    problems.append(f"{increment}: could not inspect completion proofs: {error}")
                # On a squash-merged main, origin/main is HEAD, so merge-base is the
                # delivery commit itself and cannot contain the deleted plan. Read its
                # parent for the plan and use the commit's direct diff. On an unmerged
                # topic branch, the merge-base remains the branch base and the broader
                # range is the correct delivery scope.
                changed_for_delivery = changed
                if base_ref != head:
                    changed_for_delivery = branch_changed
                production = [p for p in changed_for_delivery if p and not p.startswith("docs/") and p not in {"CLAUDE.md", "AGENTS.md"}]
                if not production:
                    problems.append(f"{increment}: plan deletion commit {head[:12]} contains no production change")
        for requirement in sorted(delivers):
            if requirement not in requirement_status:
                problems.append(f"{increment}: Delivers names unknown requirement {requirement}")
            elif requirement_status[requirement] != "Done":
                problems.append(
                    f"{increment}: delivered row names {requirement}, whose status is "
                    f"{requirement_status[requirement]}")
        if fixture_root and delivers and fixture_proof_status != "pass":
            problems.append(f"{increment}: cited proof was not observed passing in fixture run")
    elif status == "🅿️" and delivers:
        for requirement in sorted(delivers):
            if requirement not in requirement_status:
                problems.append(f"{increment}: parked row names unknown requirement {requirement}")

for increment in sorted(plan_delivers):
    if increment not in seen:
        problems.append(f"{increment}: plan is not represented by a numbered ROADMAP row")

if problems:
    for problem in problems:
        print(f"check-delivery-status: {problem}", file=sys.stderr)
    print(f"check-delivery-status: FAILED ({len(problems)} problem(s))", file=sys.stderr)
    sys.exit(1)

print(f"check-delivery-status: PASS ({len(roadmap_rows)} increment rows resolved)")
PY
