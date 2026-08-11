#!/bin/bash
# REQ-136: delivery status is derived from declared requirements and observed proof results.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bundle=""
fixture_root=""
fixture_proof_status=""
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
    if [[ -n "$bundle" ]]; then
        ./Scripts/check-proof-results.sh "$bundle" "${proof_args[@]}"
    else
        ./Scripts/check-proof-results.sh "${proof_args[@]}"
    fi
fi

python3 - "$repo_root" "$fixture_root" "$fixture_proof_status" <<'PY'
import pathlib
import re
import sys

repo = pathlib.Path(sys.argv[1])
fixture_root = pathlib.Path(sys.argv[2]) if sys.argv[2] else None
fixture_proof_status = sys.argv[3]
root = fixture_root or repo
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
for line in requirements_path.read_text().splitlines():
    if not line.startswith("| REQ-"):
        continue
    columns = [column.strip() for column in line.split("|")]
    if len(columns) < 6 or not re.fullmatch(r"REQ-\d{3}", columns[1]):
        continue
    requirement_status[columns[1]] = columns[4]

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

plan_delivers = {}
for plan_path in sorted(plans_dir.glob("*.md")):
    if plan_path.name == "README.md":
        continue
    match = re.match(r"(COR|INC|DISC)-\d+", plan_path.name)
    if not match:
        problems.append(f"{plan_path}: filename has no increment ID")
        continue
    increment = re.match(r"((?:COR|INC|DISC)-\d+)", plan_path.name).group(1)
    values = re.findall(r"^- \*\*Delivers:\*\* (.+)$", plan_path.read_text(), re.MULTILINE)
    if len(values) != 1:
        problems.append(f"{plan_path}: expected exactly one Delivers header")
        continue
    parsed = parse_delivers(f"Delivers: {values[0]}", str(plan_path))
    if parsed is not None:
        plan_delivers[increment] = parsed

plan_paths = {}
for path in sorted(plans_dir.glob("*.md")):
    if path.name == "README.md":
        continue
    match = re.match(r"((?:COR|INC|DISC)-\d+)-", path.name)
    if match:
        plan_paths.setdefault(match.group(1), []).append(path)

roadmap_rows = []
row_pattern = re.compile(r"^\s*\d+\.\s+(✅|🔵|⚪|🅿️)\s+\*\*((?:COR|INC|DISC)-\d+)\s+—")
for line_number, line in enumerate(roadmap_path.read_text().splitlines(), 1):
    match = row_pattern.match(line)
    if not match:
        continue
    status, increment = match.groups()
    delivers = parse_delivers(line, f"ROADMAP:{line_number}:{increment}")
    if delivers is not None:
        roadmap_rows.append((line_number, status, increment, delivers))

if not roadmap_rows:
    problems.append("ROADMAP contains zero numbered increment rows")

seen = set()
for line_number, status, increment, delivers in roadmap_rows:
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
        for requirement in sorted(delivers):
            if requirement not in requirement_status:
                problems.append(f"{increment}: Delivers names unknown requirement {requirement}")
            elif requirement_status[requirement] == "Done":
                problems.append(f"{increment}: active row delivers already-Done {requirement}")
    elif status == "✅":
        if plans:
            problems.append(f"ROADMAP:{line_number}:{increment}: delivered row still has a plan file")
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
