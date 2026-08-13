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
import atexit
import concurrent.futures
import hashlib
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
    dirty = subprocess.run(
        ["git", "-C", str(git_root), "status", "--porcelain", "--untracked-files=all"],
        capture_output=True, text=True, check=False,
    )
    if dirty.returncode or dirty.stdout.strip():
        problems.append("changed-scope execution requires a clean working tree")
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
        if implementation_intersects(requirement):
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
        mutation_kind = mutation.get("kind", "production")
        if mutation_kind not in {"production", "repositoryPolicy"}:
            problems.append(f"{label}: kind must be production or repositoryPolicy")
            continue
        if pathlib.Path(file_value).is_absolute() or ".." in pathlib.Path(file_value).parts:
            problems.append(f"{label}: target file must be a relative in-repository path")
            continue
        if mutation_kind == "production" and not file_value.startswith("Markdown Editor/"):
            problems.append(f"{label}: production mutation must target a file outside tests, scripts, and docs")
        if mutation_kind == "repositoryPolicy" and not file_value.startswith("Scripts/"):
            problems.append(f"{label}: repositoryPolicy mutation must target executable policy under Scripts/")
        if mutation_kind == "repositoryPolicy" and "/test-" in file_value:
            problems.append(f"{label}: repositoryPolicy mutation cannot target a fixture test")
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
        find_lines = needle.count("\n") + 1
        replacement_lines = replacement.count("\n") + 1
        if find_lines > 5 or replacement_lines > 5:
            problems.append(f"{label}: mutation must touch at most five lines (find={find_lines}, replace={replacement_lines})")
        if not isinstance(mutation.get("expect_red"), list) or not mutation["expect_red"] or not all(isinstance(item, str) and item for item in mutation["expect_red"]):
            problems.append(f"{label}: expect_red must name at least one proof")
        references = re.findall(r"`([^`]+)`", implemented_by_requirement.get(requirement, ""))
        if references:
            target_text = target.read_text(errors="ignore") if target.is_file() else ""
            production_text = "\n".join(
                path.read_text(errors="ignore")
                for path in (root / "Markdown Editor").rglob("*.swift")
            ) if (root / "Markdown Editor").is_dir() else ""
            named_responsibility = any(
                reference == file_value
                or reference.endswith("/" + file_value)
                or pathlib.Path(reference).name == pathlib.Path(file_value).name
                or re.search(rf"\b{re.escape(pathlib.Path(reference).stem)}\b", target_text)
                or re.search(rf"\b{re.escape(pathlib.Path(reference).stem)}\b", production_text)
                for reference in references
            )
            if not named_responsibility:
                problems.append(f"{label}: mutation target is not a named responsibility of {requirement}")
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


def proof_outcome(output, proof):
    if re.search(r"no tests? found|no matching tests?", output, re.IGNORECASE):
        return None
    leaf = proof.rsplit("/", 1)[-1].removesuffix("()")
    # Xcode's test runner can omit the per-case `failed` line after a crashed or
    # restarted test host and instead list the exact XCTest identifier under
    # `Failing tests:`. That is still an observed red outcome, not an empty run.
    failing_section = re.search(r"Failing tests:\s*(.*?)(?:\n\s*\*\* TEST FAILED \*\*|\Z)", output, re.DOTALL)
    if failing_section and re.search(rf"\b{re.escape(leaf)}\(\)\s*$", failing_section.group(1), re.MULTILINE):
        return "failed"
    matches = re.findall(
        rf"(?:Test case|Test Case|[◇▶✘✔] Test) [^\n]*\b{re.escape(leaf)}(?:\(\))?[^\n]*\b(passed|failed)\b",
        output,
        re.IGNORECASE,
    )
    if not matches and "/" not in proof:
        # A suite filter has one or more case lines whose identifiers carry the suite name.
        matches = re.findall(
            rf"(?:Test case|Test Case|[◇▶✘✔] Test) [^\n]*\b{re.escape(proof)}(?:/|\.)[^\n]*\b(passed|failed)\b",
            output,
            re.IGNORECASE,
        )
    if not matches:
        return None
    return matches[-1].lower()


def resolve_xcode_proof(mutant_root, proof):
    """Resolve a manifest's human-readable proof name to Xcode's test identifier."""
    if "/" in proof:
        return proof
    test_root = mutant_root / "Markdown EditorTests"
    declaration = re.compile(
        rf"(?:@Test[^\n]*\n\s*)?(?:func|static func)\s+{re.escape(proof)}\s*\("
    )
    type_declaration = re.compile(r"\b(?:struct|class|enum)\s+([A-Za-z_][A-Za-z0-9_]*)")
    for source in sorted(test_root.rglob("*.swift")):
        try:
            lines = source.read_text().splitlines()
        except (OSError, UnicodeDecodeError):
            continue
        current_type = None
        for line in lines:
            match = type_declaration.search(line)
            if match:
                current_type = match.group(1)
            if declaration.search(line) and current_type:
                return f"{source.parent.name}/{current_type}/{proof}()"
    for source in sorted(test_root.rglob("*.swift")):
        try:
            if re.search(rf"\b(?:struct|class|enum)\s+{re.escape(proof)}\b", source.read_text()):
                return f"{source.parent.name}/{proof}"
        except (OSError, UnicodeDecodeError):
            continue
    return f"{test_root.name}/{proof}"


# Execution slots.
#
# Every mutation used to get a fresh temporary tree with its own DerivedData and its own
# clonedSourcePackagesDirPath, run one at a time. That made each of the 30 mutations a cold
# build — re-resolving and recompiling cmark-gfm every time — for a ~25 minute gate on a
# project whose own DerivedData is 138 MB.
#
# A slot is a *stable* directory reused across the mutations assigned to it, so xcodebuild's
# incremental build applies: a mutation edits one file, and only that file and its dependents
# recompile. The path must be stable because Xcode's build database keys on absolute paths;
# a fresh temporary directory per mutation misses the cache by construction.
#
# Reuse has two failure directions and they are not symmetric.
#
# Staleness fails closed: a mutation that does not take effect leaves its cited proof green, and
# `all expect_red proofs remained green` is already a FAILURE. That direction needs no defence.
#
# The dangerous direction is contamination — a proof going red because of the *previous* mutation
# in this slot rather than this one, which is recorded as a PASS the manifest never earned.
# `restore()` below is the whole defence, so it is rehearsed rather than asserted:
# `Scripts/test-check-falsification.sh` runs two manifests through one slot, the second naming the
# first's proof as its own `expect_red`, and requires the gate to fail. Neutering `restore()` makes
# that fixture report `cross-mutation contamination in a reused slot unexpectedly passed` —
# observed 2026-08-11, which is the only reason this comment is allowed to claim anything.
#
# Slots are independent trees, so they run concurrently.
SLOT_COUNT = max(1, int(os.environ.get("FALSIFICATION_WORKERS", "4")))


class Slot:
    """A reusable mutant checkout: stable path, warm DerivedData, isolated HOME/TMPDIR."""

    def __init__(self, index, base):
        self.index = index
        self.root = base / f"slot-{index}"
        self.mutant_root = self.root / "repo"
        self.execution_root = self.root
        self.pristine = {}
        self.ready = False

    EXCLUDES = (".git", ".build", "DerivedData", "build", "SourcePackages", "__pycache__")

    def prepare(self):
        if self.ready:
            return
        self.ready = True
        if self.mutant_root.is_dir():
            # Reused slot. Re-sync from source before anything else, so a mutation left behind
            # by a crashed or interrupted earlier run cannot survive into this one. rsync
            # preserves mtimes, so unchanged files do not trigger a rebuild and DerivedData —
            # which lives beside repo/, not inside it — stays warm.
            command = ["rsync", "-a", "--delete"]
            for pattern in self.EXCLUDES:
                command += ["--exclude", pattern]
            command += [f"{root}/", f"{self.mutant_root}/"]
            subprocess.run(command, check=True)
        else:
            self.root.mkdir(parents=True, exist_ok=True)
            shutil.copytree(
                root,
                self.mutant_root,
                symlinks=True,
                ignore=shutil.ignore_patterns(*self.EXCLUDES),
            )
        # Script-level proofs may inspect their repository's commit identity. Never copy the
        # source checkout's linked-worktree metadata; initialize a disposable repository instead
        # so a mutant cannot read or write the user's real Git state.
        mutant_git = self.mutant_root / ".git"
        if not mutant_git.exists():
            subprocess.run(["git", "-C", str(self.mutant_root), "init", "-q"], check=True)
            subprocess.run(["git", "-C", str(self.mutant_root), "config", "user.email", "falsification@example.invalid"], check=True)
            subprocess.run(["git", "-C", str(self.mutant_root), "config", "user.name", "falsification"], check=True)
            subprocess.run(["git", "-C", str(self.mutant_root), "add", "-A"], check=True)
            subprocess.run(["git", "-C", str(self.mutant_root), "commit", "-qm", "baseline"], check=True)
        for directory in ("home", "tmp"):
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        environment = os.environ.copy()
        environment["HOME"] = str(self.root / "home")
        environment["TMPDIR"] = str(self.root / "tmp")
        self.environment = environment

    def restore(self):
        """Undo the previous mutation so this slot starts from unmutated source."""
        for relative, text in self.pristine.items():
            (self.mutant_root / relative).write_text(text)
        self.pristine.clear()

    def apply(self, relative, find, replacement):
        target = self.mutant_root / relative
        text = target.read_text()
        if text.count(find) != 1:
            return False
        self.pristine[relative] = text
        target.write_text(text.replace(find, replacement, 1))
        return True


def command_driver(mutant_root, execution_root, mutation_file=""):
    # Repository policy requirements are proved by their executable fixture, not by an
    # application test target.  Keep this driver explicit so a script mutation still has a
    # compile step (shell syntax validation) and an observed process-level proof outcome.
    if mutation_file.startswith("Scripts/") and mutation_file.endswith(".py"):
        return {
            "kind": "python-script",
            "build": ["python3", "-m", "py_compile", str(mutant_root / mutation_file)],
            "test": lambda proof, result: ["bash", str(mutant_root / proof)],
        }
    if mutation_file.startswith("Scripts/"):
        return {
            "kind": "shell",
            "build": ["bash", "-n", str(mutant_root / mutation_file)],
            "test": lambda proof, result: ["bash", str(mutant_root / proof)],
        }

    package = mutant_root / "Package.swift"
    if package.is_file():
        scratch = execution_root / "swift-build"
        cache = execution_root / "swift-cache"
        scratch.mkdir(parents=True, exist_ok=True)
        cache.mkdir(parents=True, exist_ok=True)
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
        configured_packages = os.environ.get("FALSIFICATION_SOURCE_PACKAGES")
        source_packages = pathlib.Path(configured_packages) if configured_packages else execution_root / "SourcePackages"
        source_packages.mkdir(parents=True, exist_ok=True)
        common = [
            "xcodebuild", "-project", str(project), "-scheme", project.stem,
            "-configuration", "Debug", "-derivedDataPath", str(derived_data),
            "-clonedSourcePackagesDirPath", str(source_packages),
            "-parallel-testing-enabled", "NO",
            "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=",
        ]
        return {
            "kind": "xcode",
            "build": common + ["build"],
            "test": lambda proof, result: common + [
                "-resultBundlePath", str(result), "test",
                f"-only-testing:{resolve_xcode_proof(mutant_root, proof)}",
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
            timeout=float(environment.get("FALSIFICATION_TIMEOUT_SECONDS", "600")),
        )
    except subprocess.TimeoutExpired as error:
        output = error.stdout or ""
        if isinstance(output, bytes):
            output = output.decode(errors="replace")
        return subprocess.CompletedProcess(command, 124, output + "\nfalsification command timed out")
    except OSError as error:
        return subprocess.CompletedProcess(command, 127, str(error))


def execute_mutation(slot, requirement, mutation_index, mutation):
    file_value = mutation["file"]
    find = mutation["find"]
    replacement = mutation["replace"]

    slot.prepare()
    slot.restore()
    execution_root = slot.execution_root
    mutant_root = slot.mutant_root
    environment = slot.environment

    try:
        driver = command_driver(mutant_root, execution_root, file_value)
    except RuntimeError as error:
        return False, f"{requirement} mutation {mutation_index}: {error}"

    def run_proof(proof, suffix):
        result = execution_root / f"result-{requirement}-{mutation_index}-{suffix}-{proof.replace('/', '-')}.xcresult"
        shutil.rmtree(result, ignore_errors=True)
        test = run_command(driver["test"](proof, result), mutant_root, environment)
        if driver["kind"] in {"shell", "python-script"}:
            outcome = "failed" if test.returncode else ("passed" if "PASS" in test.stdout else None)
        else:
            outcome = proof_outcome(test.stdout, proof)
        return outcome, test.stdout

    # A mutation is only discriminating when the named proof was observed green on the exact
    # preimage and red after a compiling production change. A generic gate failure or a proof that
    # was already red cannot establish REQ-138.
    for proof in mutation["expect_red"]:
        baseline, output = run_proof(proof, "baseline")
        if baseline != "passed":
            return False, (
                f"{requirement} mutation {mutation_index}: cited proof {proof!r} did not pass "
                "on the exact preimage; falsification is not discriminating\n"
                f"{describe_output(output)}"
            )

    if not slot.apply(file_value, find, replacement):
        return False, (
            f"{requirement} mutation {mutation_index}: find no longer matches exactly once "
            "in isolated tree"
        )

    build = run_command(driver["build"], mutant_root, environment)
    if build.returncode:
        return False, (
            f"{requirement} mutation {mutation_index}: mutant does not compile\n"
            f"{describe_output(build.stdout)}"
        )

    red_proofs = []
    for proof_index, proof in enumerate(mutation["expect_red"], 1):
        outcome, output = run_proof(proof, f"mutant-{proof_index}")
        if outcome is None:
            return False, (
                f"{requirement} mutation {mutation_index}: expect_red proof {proof!r} "
                "did not produce an observed named pass/fail outcome\n"
                f"{describe_output(output)}"
            )
        if outcome == "failed":
            red_proofs.append(proof)

    if not red_proofs:
        return False, (
            f"{requirement} mutation {mutation_index}: all expect_red proofs remained green"
        )
    return True, (
        f"{requirement} mutation {mutation_index}: PASS "
        f"({', '.join(red_proofs)} red)"
    )


work = [
    (requirement, index, mutation)
    for requirement in sorted(validated_manifests)
    for index, mutation in enumerate(validated_manifests[requirement]["mutations"], 1)
]

execution_failures = []
execution_passes = 0

def resolve_slot_base():
    """Warm, reusable slots for the real repository; disposable ones for fixture roots.

    A fixture root is a throwaway tree built by test-check-falsification.sh, and several
    different ones appear in one test run. Sharing a warm slot between them would carry one
    fixture's source into the next, so fixtures get a fresh base that is removed at exit.

    The real repository keys its base on a stable digest of its path — not hash(), which is
    salted per process and would produce a cold slot on every run.
    """
    if fixture is not None:
        base = pathlib.Path(tempfile.mkdtemp(prefix="falsification-fixture-slots-"))
        atexit.register(shutil.rmtree, base, True)
        return base
    configured = os.environ.get("FALSIFICATION_SLOT_DIR")
    if configured:
        base = pathlib.Path(configured)
    else:
        digest = hashlib.sha256(str(root).encode()).hexdigest()[:8]
        base = pathlib.Path(tempfile.gettempdir()) / f"falsification-slots-{digest}"
    base.mkdir(parents=True, exist_ok=True)
    return base


if work:
    slot_base = resolve_slot_base()
    slots = [Slot(index, slot_base) for index in range(min(SLOT_COUNT, len(work)))]
    total = len(work)
    completed = 0
    print(
        f"check-falsification: executing {total} mutation(s) across {len(slots)} slot(s) "
        f"in {slot_base}",
        flush=True,
    )

    def run_queue(slot, items):
        results = []
        for requirement, index, mutation in items:
            results.append((requirement, index) + execute_mutation(slot, requirement, index, mutation))
        return results

    queues = [work[offset::len(slots)] for offset in range(len(slots))]
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(slots)) as pool:
        futures = [pool.submit(run_queue, slot, items) for slot, items in zip(slots, queues)]
        for future in concurrent.futures.as_completed(futures):
            for requirement, index, passed, message in future.result():
                completed += 1
                print(
                    f"check-falsification: [{completed}/{total}] {message}",
                    file=sys.stderr if not passed else sys.stdout,
                    flush=True,
                )
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
