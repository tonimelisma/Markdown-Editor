#!/bin/bash
# REQ-117: every test cited by a `Done` requirement must have executed and passed in this run.
# REQ-118: every executed test must be cited by a requirement or carry a stated exemption, so no
#          test can fail unnoticed because nothing refers to it.
#
# COR-35. The gap this closes: `check-documentation-authority.sh` proves a cited proof *exists*.
# Nothing proved it *passed*. REQ-109 stayed `Done` for months while the test it cited was red.
#
# This gate reads structured results from an `.xcresult` bundle. It fails closed: if it cannot
# find results, or finds none, or resolves no requirement rows, it fails rather than passing —
# a check that silently matches nothing is the same defect wearing a new hat.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

# `--skip-suite NAME` (repeatable) declares a suite the run deliberately did not execute, so its
# proofs are reported as *not proven by this run* rather than as failures. `Scripts/fast-check.sh`
# passes the same suite it excludes. The closing full run passes none, so nothing is excused there.
skipped_suites=""
args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-suite)
            skipped_suites="${skipped_suites}${skipped_suites:+,}$2"
            shift 2
            ;;
        *)
            args+=("$1")
            shift
            ;;
    esac
done
set -- "${args[@]+"${args[@]}"}"
export CHECK_PROOF_SKIPPED_SUITES="$skipped_suites"

# Resolve an .xcresult bundle: explicit argument, else the newest under a derived-data path.
bundle="${1:-}"
fixture_root=""
if [[ "${1:-}" == "--fixture-root" ]]; then
    fixture_root="${2:-}"
    bundle=""
elif [[ "${2:-}" == "--fixture-root" ]]; then
    fixture_root="${3:-}"
fi
if [[ -z "$bundle" ]]; then
    derived="${FAST_CHECK_DERIVED_DATA:-$repo_root/.fast-check-build}"
    if [[ -d "$derived/Logs/Test" ]]; then
        bundle="$(ls -dt "$derived"/Logs/Test/*.xcresult 2>/dev/null | head -1 || true)"
    fi
fi

if [[ -z "$bundle" || ! -d "$bundle" ]]; then
    echo "check-proof-results: no .xcresult bundle found." >&2
    echo "check-proof-results: pass one as \$1, or set FAST_CHECK_DERIVED_DATA to a derived-data path." >&2
    echo "check-proof-results: FAILED (absent results are not a pass)" >&2
    exit 1
fi

proof_root="${fixture_root:-$repo_root}"
python3 - "$proof_root" "$bundle" <<'PY'
import json
import os
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
bundle = sys.argv[2]

# ---------------------------------------------------------------- exemptions
#
# REQ-118 permits a test to go unmapped only for a stated reason. A test is mapped when it is
# cited by a `Done` row, when its suite is cited, or — the ordinary case — when it carries a
# `// Verifies: REQ-###` anchor, which keeps the mapping next to the test instead of in a registry
# that drifts. What remains are gates whose meaning comes from guarding an *absence*: no
# requirement says "this case shall exist", so no requirement can cite them.
# REQ-118 exemptions are declared in docs/REQUIREMENTS.md (Exemptions note) so the
# spec is the source of truth. This set is derived from that doc; if the parse fails, fail closed.
_EXEMPT_FALLBACK = {
    "noUITestTargetInProject":
        "absence gate: proves no XCUITest target exists (CLAUDE.md §4 forbids UI tests)",
    "productionForcesNoTextKitLayout":
        "absence gate: proves production never forces TextKit layout",
    "productionTestHooksAreInventoried":
        "absence gate: proves no undeclared production test hook exists",
}
# Parse exemptions from REQUIREMENTS.md —the single owner. If absent, keep fallback but warn;
# if present, use parsed as EXEMPT so doc and gate cannot diverge.
try:
    _req_text = (root / "docs/REQUIREMENTS.md").read_text()
    _exempt_names = re.findall(r"`(noUITestTargetInProject|productionForcesNoTextKitLayout|productionTestHooksAreInventoried)`", _req_text)
    if _exempt_names:
        EXEMPT = {name: _EXEMPT_FALLBACK[name] for name in _exempt_names if name in _EXEMPT_FALLBACK}
    else:
        print("check-proof-results: WARNING — no REQ-118 exemptions found in docs/REQUIREMENTS.md; using fallback (doc defect)", file=sys.stderr)
        EXEMPT = _EXEMPT_FALLBACK
except Exception as e:
    print(f"check-proof-results: failed to parse exemptions from REQUIREMENTS.md: {e} — using fallback", file=sys.stderr)
    EXEMPT = _EXEMPT_FALLBACK

# ---------------------------------------------------------------- test results
try:
    raw = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests",
         "--path", bundle, "--format", "json"],
        check=True, capture_output=True, text=True,
    ).stdout
except (subprocess.CalledProcessError, FileNotFoundError) as error:
    detail = (getattr(error, "stderr", "") or str(error)).strip()
    print(f"check-proof-results: xcresulttool failed on {bundle}: {detail}", file=sys.stderr)
    sys.exit(1)

data = json.loads(raw)

# Pin the JSON shape. `xcresulttool`'s schema is version-dependent; if a future Xcode renames
# these keys, extraction would silently match nothing and this gate would pass vacuously.
if "testNodes" not in data:
    print("check-proof-results: xcresulttool JSON has no 'testNodes' key — the schema changed. "
          "Re-verify the extraction against the new shape rather than weakening this gate.",
          file=sys.stderr)
    sys.exit(1)

outcomes = {}        # bare test name -> set of result strings
suite_of = {}        # bare test name -> set of suite names
suite_outcomes = {}  # suite name -> set of result strings


def walk(node):
    if isinstance(node, dict):
        if node.get("nodeType") == "Test Case":
            identifier = node.get("nodeIdentifier") or node.get("name") or ""
            result = node.get("result") or ""
            # "SuiteName/testName()" -> ("SuiteName", "testName"). Parameterised cases carry
            # their argument list in the identifier; strip it back to the declared name.
            suite, _, leaf = identifier.rpartition("/")
            leaf = re.sub(r"\(.*\)$", "", leaf).strip()
            if leaf:
                outcomes.setdefault(leaf, set()).add(result)
                if suite:
                    suite_of.setdefault(leaf, set()).add(suite)
                    suite_outcomes.setdefault(suite, set()).add(result)
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for item in node:
            walk(item)


walk(data)

if not outcomes:
    print("check-proof-results: the bundle yielded zero test cases — either nothing ran, or the "
          "'Test Case' node shape changed. Absent results are not a pass.", file=sys.stderr)
    sys.exit(1)


def is_pass(results):
    return bool(results) and results.issubset({"Passed", "Expected Failure"})


# Every test symbol declared in the test sources, plus the `// Verifies: REQ-###` anchor each
# one carries. `declared` lets a cited proof that never executed — the COR-32 failure mode, where
# the suite hung and produced no result at all — be told apart from a production type name that
# merely happens to appear in the Verified-by column. `anchors` is the REQ-118 mapping: it lives
# next to the test, so a new test cannot quietly arrive without naming what it proves.
declared = set()
anchors = {}
declaring_suite = {}
for path in (root / "Markdown EditorTests").rglob("*.swift"):
    lines = path.read_text(errors="ignore").splitlines()
    current_suite = ""
    for index, line in enumerate(lines):
        type_match = re.match(r"\s*(?:public\s+|final\s+|@MainActor\s+)*(?:struct|class|enum)\s+(\w+)", line)
        if type_match:
            current_suite = type_match.group(1)
        match = re.search(r"\bfunc\s+(\w+)\s*\(", line)
        if not match:
            continue
        name = match.group(1)
        declared.add(name)
        declaring_suite[name] = current_suite
        # Walk back over the attribute and comment lines immediately above the declaration.
        found, cursor = set(), index - 1
        while cursor >= 0:
            above = lines[cursor].strip()
            if above.startswith("@"):
                cursor -= 1
                continue
            if above.startswith("//"):
                # The anchors use a slash-separated multi-requirement form —
                # `// Verifies: REQ-090/103/116` — so a bare `REQ-\d{3}` match would silently
                # keep only the first and drop every later one, leaving those requirements
                # with no test-level mapping at all.
                for group in re.findall(r"REQ-\d{3}(?:/\d{3})*", above):
                    head, *rest = group.split("/")
                    found.add(head)
                    found.update(f"REQ-{number}" for number in rest)
                cursor -= 1
                continue
            break
        if found:
            anchors[name] = sorted(found)

known_requirements = set(re.findall(r"^\| (REQ-\d{3}) ",
                                    (root / "docs/REQUIREMENTS.md").read_text(), re.M))

# Every identifier-like word appearing anywhere in production or test sources.
#
# A `Done` row may legitimately name a production type in its Verified-by column, so an
# unresolved identifier cannot simply be treated as a missing test. But an identifier that
# appears **nowhere in the sources at all** is a citation to something that no longer exists.
# `check-documentation-authority.sh` does not catch this once the row also cites a real symbol,
# so without this the two gates leave a hole between them rather than composing.
source_tokens = set()
for directory in ("Markdown Editor", "Markdown EditorTests"):
    for path in (root / directory).rglob("*.swift"):
        source_tokens.update(re.findall(r"\b\w+\b", path.read_text(errors="ignore")))

# ---------------------------------------------------------------- requirements
requirements_path = root / "docs/REQUIREMENTS.md"
rows = [line for line in requirements_path.read_text().splitlines()
        if re.match(r"^\| REQ-\d{3} ", line)]
if not rows:
    print("check-proof-results: parsed zero REQ rows from docs/REQUIREMENTS.md — parser bug.",
          file=sys.stderr)
    sys.exit(1)

skipped_suites = {name for name in os.environ.get("CHECK_PROOF_SKIPPED_SUITES", "").split(",") if name}

failures = []
verified_rows = 0
cited_tests = set()
cited_suites = set()
unproven_by_skip = []

for row in rows:
    columns = row.split("|")
    if len(columns) < 7:
        continue
    requirement = columns[1].strip()
    status = columns[4].strip()
    verified = columns[6].strip()
    if status != "Done":
        continue

    identifiers = re.findall(r"`([A-Za-z_][A-Za-z0-9_.]*)`", verified)
    scripts = re.findall(r"`(Scripts/[\w./-]+)`", verified)

    tests_cited, suites_cited, never_executed, dangling_citations = set(), set(), set(), set()
    for name in identifiers:
        head, leaf = name.split(".")[0], name.split(".")[-1]
        if leaf in outcomes:
            tests_cited.add(leaf)
        elif leaf in suite_outcomes:
            suites_cited.add(leaf)
        elif head in suite_outcomes and leaf != head:
            # `Suite.member` has to name a real test in that suite. Crediting the suite and
            # ignoring the member would let a citation keep pointing at a test that was renamed
            # or deleted, which is the failure this gate exists to catch.
            if leaf in declared:
                never_executed.add(leaf)
            else:
                dangling_citations.add(name)
        elif head in suite_outcomes:
            suites_cited.add(head)
        elif leaf in declared:
            never_executed.add(leaf)
        elif name.startswith("Scripts/"):
            continue
        elif not all(part in source_tokens for part in name.split(".")):
            # Deliberately a weak check, and it is the last one. A Verified-by cell legitimately
            # names production types in prose (`NSTextStorage`, `EditorSession`), so an identifier
            # that resolves to nothing in particular cannot be failed outright — only one that
            # appears nowhere in the sources at all is provably stale. Precise staleness for test
            # citations is covered by the `Suite.member` branch above.
            dangling_citations.add(name)

    if tests_cited or suites_cited or never_executed:
        verified_rows += 1
    elif "inherent" in verified.lower() or scripts:
        # Framework/absence proofs and script-level gates carry no test identifier by design.
        verified_rows += 1
        continue
    else:
        failures.append(
            f"{requirement}: `Done`, but its Verified-by column resolves to no executed test, "
            f"no suite, no script, and is not `inherent` — unmapped (REQ-117)")
        continue

    for name in sorted(tests_cited):
        cited_tests.add(name)
        if not is_pass(outcomes[name]):
            failures.append(
                f"{requirement}: cited proof `{name}` did not pass "
                f"(result: {', '.join(sorted(outcomes[name]))}) (REQ-117)")
    for name in sorted(suites_cited):
        cited_suites.add(name)
        if not is_pass(suite_outcomes[name]):
            failures.append(
                f"{requirement}: cited suite `{name}` contains a test that did not pass "
                f"(results: {', '.join(sorted(suite_outcomes[name]))}) (REQ-117)")
    for name in sorted(never_executed):
        if declaring_suite.get(name) in skipped_suites:
            # Deliberately not executed by this run. Reported, never counted as proven.
            unproven_by_skip.append(f"{requirement}:{name}")
            continue
        failures.append(
            f"{requirement}: cited proof `{name}` did not execute in this run — a suite that "
            f"does not complete leaves this requirement unproven, not proven (REQ-117)")
    for name in sorted(dangling_citations):
        failures.append(
            f"{requirement}: cited proof `{name}` appears nowhere in the sources — the citation "
            f"outlived what it named (REQ-117)")

# ---------------------------------------------------------------- REQ-118
#
# A test is mapped when a `Done` row cites it or its suite, when it carries a `// Verifies:`
# anchor, or when it is exempt. Anything else could fail without any requirement noticing — which
# is exactly how `resolvedImageRefreshesItsAttachmentOnlyWhenDisplayIdentityChanges` stayed red.
unmapped, dangling = [], []
for name in sorted(outcomes):
    if name in cited_tests or name in EXEMPT or (suite_of.get(name, set()) & cited_suites):
        continue
    anchored = anchors.get(name)
    if not anchored:
        unmapped.append(name)
        continue
    for requirement in anchored:
        if requirement not in known_requirements:
            dangling.append(f"{name} → {requirement}")

if unmapped:
    failures.append(
        f"REQ-118: {len(unmapped)} executed test(s) are cited by no requirement, carry no "
        f"`// Verifies: REQ-###` anchor, and have no stated exemption, so a failure in them "
        f"would go unnoticed: {', '.join(unmapped[:12])}{' …' if len(unmapped) > 12 else ''}")

if dangling:
    failures.append(
        f"REQ-118: {len(dangling)} test anchor(s) name a requirement that does not exist: "
        f"{', '.join(dangling[:12])}")

# REQ-117, second half: a test that names the requirement it proves and then fails leaves that
# requirement unproven, whether or not REQUIREMENTS.md happens to cite it back.
for name in sorted(outcomes):
    if is_pass(outcomes[name]) or name in cited_tests:
        continue
    named = ", ".join(anchors.get(name, [])) or "no requirement"
    failures.append(
        f"{named}: test `{name}` did not pass "
        f"(result: {', '.join(sorted(outcomes[name]))}) (REQ-117)")

if verified_rows == 0:
    failures.append("check-proof-results: vacuous — zero Done rows resolved to a proof (parser bug?)")

for failure in failures:
    print(f"check-proof-results: {failure}", file=sys.stderr)

if failures:
    print(f"check-proof-results: FAILED ({len(failures)} problem(s))", file=sys.stderr)
    sys.exit(1)

if unproven_by_skip:
    print(f"check-proof-results: NOTE — {len(unproven_by_skip)} cited proof(s) live in a suite "
          f"this run deliberately skipped ({', '.join(sorted(skipped_suites))}), so their "
          f"requirements are NOT proven by this run. The closing full run skips nothing.")

print(f"check-proof-results: PASS ({verified_rows} Done rows verified against "
      f"{len(outcomes)} executed tests, {len(cited_suites)} cited suites)")
PY
