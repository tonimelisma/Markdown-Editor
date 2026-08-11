#!/bin/bash
# COR-60 / REQ-137: committed benchmark tables must carry machine-verifiable provenance.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
research_root="$repo_root/docs/research"
fixture_root=""
expected_digest=""
fixture_mode=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --research-root)
            [[ $# -ge 2 ]] || { echo "usage: check-measurement-provenance.sh [--research-root DIR] [--fixture-root DIR] [--expected-corpus-digest DIGEST]" >&2; exit 2; }
            research_root="$2"
            shift 2
            ;;
        --fixture-root)
            [[ $# -ge 2 ]] || { echo "usage: check-measurement-provenance.sh [--research-root DIR] [--fixture-root DIR] [--expected-corpus-digest DIGEST]" >&2; exit 2; }
            fixture_root="$2"
            research_root="$2/docs/research"
            fixture_mode=1
            shift 2
            ;;
        --expected-corpus-digest)
            [[ $# -ge 2 ]] || { echo "usage: check-measurement-provenance.sh [--research-root DIR] [--fixture-root DIR] [--expected-corpus-digest DIGEST]" >&2; exit 2; }
            expected_digest="$2"
            shift 2
            ;;
        --help)
            echo "usage: check-measurement-provenance.sh [--research-root DIR] [--fixture-root DIR] [--expected-corpus-digest DIGEST]"
            exit 0
            ;;
        *)
            echo "check-measurement-provenance: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if [[ -n "$expected_digest" && "$fixture_mode" -ne 1 ]]; then
    echo "check-measurement-provenance: --expected-corpus-digest is fixture-only" >&2
    exit 2
fi

python3 - "$repo_root" "$research_root" "$fixture_root" "$expected_digest" <<'PY'
import pathlib
import re
import subprocess
import sys

repo = pathlib.Path(sys.argv[1])
research = pathlib.Path(sys.argv[2])
fixture_root = research.parent.parent if sys.argv[3] else None
expected_digest = sys.argv[4]
git_root = repo
problems = []

if not research.is_dir():
    print(f"check-measurement-provenance: missing research directory: {research}", file=sys.stderr)
    sys.exit(1)

# COR-45 owns the executable PerformanceCorpus digest producer. Until it exists, a committed
# benchmark table must fail closed rather than treating a source-file hash as a corpus digest.
corpus_digest = expected_digest if fixture_root else ""

def has_results_table(text):
    # This is the benchmark schema, not every ordinary evidence table in research. COR-45 owns
    # PerformanceCorpus and will keep this schema stable when it returns.
    return bool(re.search(r"^\|\s*scenario\s*\|\s*corpus\s*\|", text, re.MULTILINE | re.IGNORECASE))

def field(text, name):
    pattern = rf"(?:^|\n)(?:[-*]\s*)?\*?\*?{re.escape(name)}\*?\*?\s*:\s*([^\n]+)"
    match = re.search(pattern, text, re.IGNORECASE)
    return match.group(1).strip() if match else ""

def reject_constructs(text, path):
    for token in ("$(", "${", "`"):
        if token in text:
            problems.append(f"{path}: unexpanded shell construct {token!r}")

for path in sorted(research.glob("*.md")):
    if path.name == "README.md":
        continue
    text = path.read_text()
    if not has_results_table(text):
        continue
    reject_constructs(text, path)
    required = {
        "Host": field(text, "Host"),
        "OS": field(text, "OS"),
        "OS build": field(text, "OS build"),
        "Architecture": field(text, "Architecture"),
        "Configuration": field(text, "Configuration"),
        "Xcode": field(text, "Xcode"),
        "Corpus digest": field(text, "Corpus digest"),
        "Warmup": field(text, "Warmup"),
        "Samples": field(text, "Samples"),
        "Interval": field(text, "Interval"),
        "Commit": field(text, "Commit"),
        "Run ID": field(text, "Run ID"),
    }
    for name, value in required.items():
        if not value:
            problems.append(f"{path}: missing provenance field {name}")
            continue
        if re.search(r"stub|placeholder|unknown|unavailable|not recorded|not applicable|^n/?a$|^tbd$", value, re.IGNORECASE):
            problems.append(f"{path}: placeholder provenance field {name}: {value}")
    commit = required["Commit"]
    if commit and not re.fullmatch(r"[0-9a-fA-F]{7,40}", commit):
        problems.append(f"{path}: Commit is not a SHA: {commit}")
    elif commit:
        result = subprocess.run(["git", "-C", str(git_root), "cat-file", "-e", f"{commit}^{{commit}}"], capture_output=True)
        if result.returncode:
            problems.append(f"{path}: Commit does not exist in this repository: {commit}")
    if required["Corpus digest"] and corpus_digest and required["Corpus digest"] != corpus_digest:
        problems.append(f"{path}: corpus digest does not match current PerformanceCorpus")
    if required["Corpus digest"] and not corpus_digest:
        problems.append(f"{path}: current PerformanceCorpus is unavailable; cannot verify corpus digest")

if problems:
    for problem in problems:
        print(f"check-measurement-provenance: {problem}", file=sys.stderr)
    print(f"check-measurement-provenance: FAILED ({len(problems)} problem(s))", file=sys.stderr)
    sys.exit(1)

print("check-measurement-provenance: PASS")
PY
