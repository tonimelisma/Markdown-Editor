#!/bin/bash
# COR-61 / REQ-138: Phase 1 manifest schema gate.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture_root=""
mode=""
range=""

usage() {
    echo "usage: check-falsification.sh --all | --changed BASE..HEAD [--fixture-root DIR]" >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            [[ -z "$mode" ]] || { usage; exit 2; }
            mode=all
            shift
            ;;
        --changed)
            [[ $# -ge 2 && -z "$mode" ]] || { usage; exit 2; }
            mode=changed
            range="$2"
            shift 2
            ;;
        --fixture-root)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            fixture_root="$2"
            shift 2
            ;;
        --help)
            usage >&1
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

[[ -n "$mode" ]] || { usage; exit 2; }

python3 - "$repo_root" "$fixture_root" "$mode" "$range" <<'PY'
import json
import pathlib
import re
import subprocess
import sys

repo = pathlib.Path(sys.argv[1])
fixture = pathlib.Path(sys.argv[2]) if sys.argv[2] else None
mode = sys.argv[3]
range_value = sys.argv[4]
root = fixture or repo
requirements_path = root / "docs/REQUIREMENTS.md"
manifest_dir = root / "Falsification"
problems = []

if not requirements_path.is_file():
    problems.append("missing docs/REQUIREMENTS.md")
if not manifest_dir.is_dir():
    problems.append("missing Falsification directory")
if problems:
    for problem in problems:
        print(f"check-falsification: {problem}", file=sys.stderr)
    sys.exit(1)

done = set()
for line in requirements_path.read_text().splitlines():
    columns = [column.strip() for column in line.split("|")]
    if len(columns) >= 6 and re.fullmatch(r"REQ-\d{3}", columns[1]) and columns[4] == "Done":
        done.add(columns[1])

manifest_paths = sorted(manifest_dir.glob("REQ-*.json"))
manifest_ids = set()
for path in manifest_paths:
    if not re.fullmatch(r"REQ-\d{3}\.json", path.name):
        problems.append(f"{path}: filename must be REQ-###.json")
    else:
        manifest_ids.add(path.stem)

selected = done
if mode == "changed" and not fixture:
    changed = subprocess.run(
        ["git", "-C", str(repo), "diff", "--name-only", range_value],
        capture_output=True, text=True, check=False
    )
    if changed.returncode:
        problems.append(f"cannot inspect changed range {range_value}")
    touched = set(changed.stdout.splitlines())
    selected = set()
    for requirement in done:
        manifest = manifest_dir / f"{requirement}.json"
        if manifest.exists() and str(manifest.relative_to(root)) in touched:
            selected.add(requirement)
        try:
            data = json.loads(manifest.read_text()) if manifest.exists() else {}
            for mutation in data.get("mutations", []):
                if mutation.get("file") in touched:
                    selected.add(requirement)
        except (json.JSONDecodeError, OSError):
            selected.add(requirement)

for requirement in sorted(selected):
    path = manifest_dir / f"{requirement}.json"
    if not path.is_file():
        problems.append(f"{requirement}: Done requirement has no falsification manifest")
        continue
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as error:
        problems.append(f"{path}: invalid JSON: {error}")
        continue
    if data.get("requirement") != requirement:
        problems.append(f"{path}: requirement field does not match filename")
    mutations = data.get("mutations")
    if not isinstance(mutations, list) or not mutations:
        problems.append(f"{path}: mutations must be a non-empty array")
        continue
    for index, mutation in enumerate(mutations, 1):
        label = f"{path} mutation {index}"
        if not isinstance(mutation, dict):
            problems.append(f"{label}: must be an object")
            continue
        for field in ("rationale", "file", "find", "replace", "expect_red"):
            if not mutation.get(field):
                problems.append(f"{label}: missing {field}")
        target = root / mutation.get("file", "")
        needle = mutation.get("find", "")
        replacement = mutation.get("replace", "")
        file_value = mutation.get("file", "")
        if not isinstance(file_value, str) or pathlib.Path(file_value).is_absolute() or ".." in pathlib.Path(file_value).parts:
            problems.append(f"{label}: target file must be a relative in-repository path")
            continue
        if not file_value.startswith("Markdown Editor/"):
            problems.append(f"{label}: target file must be production source under Markdown Editor/")
            continue
        target = (root / file_value).resolve()
        try:
            target.relative_to(root.resolve())
        except ValueError:
            problems.append(f"{label}: target file escapes repository root")
            continue
        if not target.is_file():
            problems.append(f"{label}: target file does not exist: {mutation.get('file')}")
        elif target.read_text().count(needle) != 1:
            problems.append(f"{label}: find must match exactly once in {mutation.get('file')}")
        if any(token in replacement for token in ("fatalError", "preconditionFailure", "FIXME", "abort(", "while true")):
            problems.append(f"{label}: replacement is a degenerate kill mutation")
        if replacement.count("\n") - needle.count("\n") > 5 or needle.count("\n") - replacement.count("\n") > 5:
            problems.append(f"{label}: replacement changes more than five lines")
        if not isinstance(mutation.get("expect_red"), list) or not mutation["expect_red"] or not all(isinstance(item, str) and item for item in mutation["expect_red"]):
            problems.append(f"{label}: expect_red must name at least one proof")

for manifest_id in sorted(manifest_ids - done):
    problems.append(f"{manifest_id}: manifest has no current Done requirement")

if problems:
    for problem in problems:
        print(f"check-falsification: {problem}", file=sys.stderr)
    print(f"check-falsification: FAILED ({len(problems)} problem(s))", file=sys.stderr)
    sys.exit(1)

print(f"check-falsification: PASS ({len(selected)} manifest(s) structurally valid; execution phase not yet enabled)")
PY
