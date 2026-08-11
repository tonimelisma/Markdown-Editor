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
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

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
implemented_by_requirement = {}
for line in requirements_path.read_text().splitlines():
    columns = [column.strip() for column in line.split("|")]
    if len(columns) >= 6 and re.fullmatch(r"REQ-\d{3}", columns[1]) and columns[4] == "Done":
        done.add(columns[1])
        implemented_by_requirement[columns[1]] = columns[5]

manifest_paths = sorted(manifest_dir.glob("REQ-*.json"))
manifest_ids = set()
for path in manifest_paths:
    if not re.fullmatch(r"REQ-\d{3}\.json", path.name):
        problems.append(f"{path}: filename must be REQ-###.json")
    else:
        manifest_ids.add(path.stem)

selected = done
git_root = root if fixture and (root / ".git").exists() else repo
if mode == "changed" and (not fixture or (root / ".git").exists()):
    changed = subprocess.run(
        ["git", "-C", str(git_root), "diff", "--name-only", range_value],
        capture_output=True, text=True, check=False
    )
    if changed.returncode:
        problems.append(f"cannot inspect changed range {range_value}")
    touched = set(changed.stdout.splitlines())

    def changed_file_contains(token, relative_path):
        # Traceability symbols are resolved against production source. Searching manifests,
        # prose, or gate scripts would select unrelated requirements merely because a rationale
        # mentions the same type name.
        if not relative_path.endswith(".swift"):
            return False
        path = root / relative_path
        if not path.is_file():
            return False
        try:
            text = path.read_text()
        except (OSError, UnicodeDecodeError):
            return False
        return token in text

    def implementation_intersects(requirement):
        implemented = implemented_by_requirement.get(requirement, "")
        references = re.findall(r"`([^`]+)`", implemented)
        for relative_path in touched:
            if not relative_path:
                continue
            path = pathlib.Path(relative_path)
            if any(
                reference == relative_path
                or reference.endswith("/" + relative_path)
                or pathlib.Path(reference).name == path.name
                for reference in references
            ):
                return True
            if any(changed_file_contains(reference, relative_path) for reference in references):
                return True
        return False

    selected = set()
    for requirement in done:
        manifest = manifest_dir / f"{requirement}.json"
        if manifest.exists() and str(manifest.relative_to(root)) in touched:
            selected.add(requirement)
        if implementation_intersects(requirement):
            selected.add(requirement)
        try:
            data = json.loads(manifest.read_text()) if manifest.exists() else {}
            for mutation in data.get("mutations", []):
                if mutation.get("file") in touched:
                    selected.add(requirement)
        except (json.JSONDecodeError, OSError):
            selected.add(requirement)

validated_manifests = {}
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
        file_value = mutation.get("file", "")
        needle = mutation.get("find", "")
        replacement = mutation.get("replace", "")
        if not isinstance(file_value, str):
            problems.append(f"{label}: target file must be a string")
            continue
        if not isinstance(needle, str):
            problems.append(f"{label}: find must be a string")
            continue
        if not isinstance(replacement, str):
            problems.append(f"{label}: replace must be a string")
            continue
        if pathlib.Path(file_value).is_absolute() or ".." in pathlib.Path(file_value).parts:
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
    if not any(problem.startswith(f"{path}:") for problem in problems):
        validated_manifests[requirement] = data

for manifest_id in sorted(manifest_ids - done):
    problems.append(f"{manifest_id}: manifest has no current Done requirement")

if problems:
    for problem in problems:
        print(f"check-falsification: {problem}", file=sys.stderr)
    print(f"check-falsification: FAILED ({len(problems)} problem(s))", file=sys.stderr)
    sys.exit(1)

def describe_output(output):
    lines = output.strip().splitlines()
    if len(lines) > 30:
        lines = lines[-30:]
    return "\n".join(lines)


def test_was_executed(output):
    if re.search(r"no tests? found|no matching tests?", output, re.IGNORECASE):
        return False
    return bool(re.search(
        r"(?:Test run with [1-9][0-9]* test|Executed [1-9][0-9]* test|"
        r"Test (?:Suite|Case) .+ (?:started|passed|failed)|"
        r"[◇▶] Test .+ started)",
        output,
        re.IGNORECASE,
    ))


def command_driver(mutant_root, execution_root):
    package = mutant_root / "Package.swift"
    if package.is_file():
        scratch = execution_root / "swift-build"
        cache = execution_root / "swift-cache"
        scratch.mkdir()
        cache.mkdir()
        swiftpm = [
            "--package-path", str(mutant_root), "--scratch-path", str(scratch),
            "--cache-path", str(cache), "--manifest-cache", "local",
            "--disable-sandbox",
        ]
        return {
            "kind": "swift-package",
            "build": ["swift", "build"] + swiftpm,
            "test": lambda proof, result: ["swift", "test"] + swiftpm + ["--filter", proof],
        }

    projects = sorted(mutant_root.glob("*.xcodeproj"))
    if len(projects) == 1:
        project = projects[0]
        derived_data = execution_root / "DerivedData"
        source_packages = execution_root / "SourcePackages"
        source_packages.mkdir()
        common = [
            "xcodebuild", "-project", str(project), "-scheme", project.stem,
            "-configuration", "Debug", "-derivedDataPath", str(derived_data),
            "-clonedSourcePackagesDirPath", str(source_packages),
            "-parallel-testing-enabled", "NO",
        ]
        return {
            "kind": "xcode",
            "build": common + ["build"],
            "test": lambda proof, result: common + [
                "-resultBundlePath", str(result), "test",
                f"-only-testing:{project.stem}Tests/{proof}",
            ],
        }

    raise RuntimeError(
        "cannot determine Swift compile/test driver (expected Package.swift or one .xcodeproj)"
    )


def run_command(command, cwd, environment):
    try:
        return subprocess.run(
            command,
            cwd=cwd,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
    except OSError as error:
        return subprocess.CompletedProcess(command, 127, str(error))


def execute_mutation(requirement, mutation_index, mutation):
    file_value = mutation["file"]
    source_path = root / file_value
    original = source_path.read_text()
    find = mutation["find"]
    replacement = mutation["replace"]

    with tempfile.TemporaryDirectory(prefix=f"falsification-{requirement}-") as temporary:
        execution_root = pathlib.Path(temporary)
        mutant_root = execution_root / "repo"
        shutil.copytree(
            root,
            mutant_root,
            symlinks=True,
            ignore=shutil.ignore_patterns(
                ".git", ".build", "DerivedData", "build", "SourcePackages",
                "__pycache__",
            ),
        )
        mutant_source = mutant_root / file_value
        if mutant_source.read_text().count(find) != 1:
            return False, (
                f"{requirement} mutation {mutation_index}: find no longer matches exactly once "
                "in isolated tree"
            )
        mutant_source.write_text(original.replace(find, replacement, 1))

        isolated_home = execution_root / "home"
        isolated_tmp = execution_root / "tmp"
        isolated_home.mkdir()
        isolated_tmp.mkdir()
        environment = os.environ.copy()
        environment["HOME"] = str(isolated_home)
        environment["TMPDIR"] = str(isolated_tmp)

        try:
            driver = command_driver(mutant_root, execution_root)
        except RuntimeError as error:
            return False, f"{requirement} mutation {mutation_index}: {error}"

        build = run_command(driver["build"], mutant_root, environment)
        if build.returncode:
            return False, (
                f"{requirement} mutation {mutation_index}: mutant does not compile\n"
                f"{describe_output(build.stdout)}"
            )

        red_proofs = []
        for proof_index, proof in enumerate(mutation["expect_red"], 1):
            result = execution_root / f"result-{proof_index}.xcresult"
            test = run_command(driver["test"](proof, result), mutant_root, environment)
            if not test_was_executed(test.stdout):
                return False, (
                    f"{requirement} mutation {mutation_index}: expect_red proof {proof!r} "
                    "did not execute\n"
                    f"{describe_output(test.stdout)}"
                )
            if test.returncode:
                red_proofs.append(proof)

        if not red_proofs:
            return False, (
                f"{requirement} mutation {mutation_index}: all expect_red proofs remained green"
            )
        return True, (
            f"{requirement} mutation {mutation_index}: PASS "
            f"({', '.join(red_proofs)} red)"
        )


execution_failures = []
execution_passes = 0
for requirement in sorted(validated_manifests):
    for mutation_index, mutation in enumerate(validated_manifests[requirement]["mutations"], 1):
        passed, message = execute_mutation(requirement, mutation_index, mutation)
        print(f"check-falsification: {message}", file=sys.stderr if not passed else sys.stdout)
        if not passed:
            execution_failures.append(message)
        else:
            execution_passes += 1

if execution_failures:
    print(
        f"check-falsification: FAILED ({len(execution_failures)} mutation(s) failed execution)",
        file=sys.stderr,
    )
    sys.exit(1)

print(
    f"check-falsification: PASS ({len(selected)} manifest(s) structurally valid; "
    f"{execution_passes} mutation(s) falsified their cited proof(s))"
)
PY
