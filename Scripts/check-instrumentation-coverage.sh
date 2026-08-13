#!/bin/bash
# REQ-099/135: trace vocabulary coverage is proved by emitted JSON Lines, not source text.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cases_file="$repo_root/Markdown Editor/EditorTrace.swift"
exemptions_file="$repo_root/docs/trace-coverage-exemptions.md"
routes_file="$repo_root/docs/proof-routes.json"
log_dirs=()

usage() {
    echo "usage: check-instrumentation-coverage.sh --log-dir <directory> [--log-dir <directory>]" >&2
    exit 2
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --log-dir) [[ $# -ge 2 ]] || usage; log_dirs+=("$2"); shift 2 ;;
        --cases-file) [[ $# -ge 2 ]] || usage; cases_file="$2"; shift 2 ;;
        --exemptions) [[ $# -ge 2 ]] || usage; exemptions_file="$2"; shift 2 ;;
        --routes) [[ $# -ge 2 ]] || usage; routes_file="$2"; shift 2 ;;
        *) usage ;;
    esac
done
if [[ ${#log_dirs[@]} -eq 0 && -n "${INSTRUMENTATION_LOG_DIRS:-}" ]]; then
    IFS=: read -r -a log_dirs <<<"$INSTRUMENTATION_LOG_DIRS"
fi
if [[ ${#log_dirs[@]} -eq 0 ]]; then
    echo "instrumentation-coverage: no diagnostic log directories supplied" >&2
    exit 1
fi
python3 - "$cases_file" "$exemptions_file" "$routes_file" "${log_dirs[@]}" <<'PY'
import json
import pathlib
import re
import sys

cases_path = pathlib.Path(sys.argv[1])
exemptions_path = pathlib.Path(sys.argv[2])
routes_path = pathlib.Path(sys.argv[3])
log_dirs = [pathlib.Path(value) for value in sys.argv[4:]]

if not cases_path.is_file():
    raise SystemExit(f"instrumentation-coverage: missing case source {cases_path}")
if not exemptions_path.is_file():
    raise SystemExit(f"instrumentation-coverage: missing exemption record {exemptions_path}")
if not routes_path.is_file():
    raise SystemExit(f"instrumentation-coverage: missing proof-route mapping {routes_path}")

case_text = cases_path.read_text(encoding="utf-8")
if cases_path.name == "EditorTrace.swift":
    block = re.search(r"nonisolated enum EditorTraceEvent.*?^}", case_text, re.M | re.S)
    if not block:
        raise SystemExit("instrumentation-coverage: EditorTraceEvent enumeration not found")
    cases = set(re.findall(r"^    case\s+([A-Za-z_]\w*)", block.group(0), re.M))
else:
    cases = {line.strip() for line in case_text.splitlines() if line.strip()}
if not cases:
    raise SystemExit("instrumentation-coverage: zero trace cases extracted")

try:
    route_document = json.loads(routes_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"instrumentation-coverage: invalid proof-route mapping: {error}")
routes = route_document.get("events") if isinstance(route_document, dict) else None
if not isinstance(routes, dict):
    raise SystemExit("instrumentation-coverage: proof-route mapping has no events object")
if set(routes) != cases:
    missing_routes = sorted(cases - set(routes))
    unknown_routes = sorted(set(routes) - cases)
    detail = []
    if missing_routes:
        detail.append(f"missing {missing_routes}")
    if unknown_routes:
        detail.append(f"unknown {unknown_routes}")
    raise SystemExit("instrumentation-coverage: proof-route mapping does not match vocabulary (" + "; ".join(detail) + ")")
for name, route in routes.items():
    if not isinstance(route, dict) or not all(isinstance(route.get(key), str) and route[key] for key in ("owner", "entry", "expectedRecord", "allowedHarness")):
        raise SystemExit(f"instrumentation-coverage: route for {name} is incomplete")
    if route["expectedRecord"] != name:
        raise SystemExit(f"instrumentation-coverage: route for {name} expects {route['expectedRecord']!r}")
    def code_only(source):
        output = list(source)
        index = 0
        while index < len(source):
            if source.startswith("//", index):
                end = source.find("\n", index)
                end = len(source) if end < 0 else end
                for position in range(index, end):
                    output[position] = " "
                index = end
                continue
            if source.startswith("/*", index):
                end = source.find("*/", index + 2)
                end = len(source) - 2 if end < 0 else end
                for position in range(index, min(len(source), end + 2)):
                    if source[position] != "\n":
                        output[position] = " "
                index = min(len(source), end + 2)
                continue
            if source[index] == '"':
                index += 1
                while index < len(source):
                    if source[index] == "\\":
                        index += 2
                    elif source[index] == '"':
                        index += 1
                        break
                    else:
                        if source[index] != "\n":
                            output[index] = " "
                        index += 1
                continue
            index += 1
        return "".join(output)

    def matching_brace(source, opening):
        depth = 0
        for position in range(opening, len(source)):
            if source[position] == "{":
                depth += 1
            elif source[position] == "}":
                depth -= 1
                if depth == 0:
                    return position
        return None

    def type_body(source, type_path):
        current = source
        for type_name in type_path.split("."):
            owner_match = re.search(
                rf"\b(?:class|struct|enum)\s+{re.escape(type_name)}\b[^{{]*{{", current
            )
            if not owner_match:
                return None
            owner_opening = current.find("{", owner_match.start())
            owner_end = matching_brace(current, owner_opening)
            if owner_end is None:
                raise SystemExit(f"instrumentation-coverage: unterminated owner {type_path}")
            current = current[owner_opening + 1:owner_end]
        return current

    owner_sources = []
    for path in cases_path.parent.rglob("*.swift"):
        if "Markdown EditorTests" in path.parts:
            continue
        source = path.read_text(encoding="utf-8", errors="ignore")
        code = code_only(source)
        owner = type_body(code, route["owner"])
        if owner is not None:
            owner_sources.append(owner)
    if not owner_sources:
        raise SystemExit(f"instrumentation-coverage: route for {name} names an absent production owner")
    entry_pattern = re.compile(rf"\bfunc\s+{re.escape(route['entry'])}\s*\(")
    if name == "workLedger":
        route_pattern = re.compile(r"\brecordProduction\s*\(.*?\broute:\s*\.workLedger\b", re.S)
    else:
        route_pattern = re.compile(
            rf"\brecord\s*\(\s*route:\s*\.{re.escape(name)}\s*,\s*\.{re.escape(name)}\b"
        )
    bound = False
    for source in owner_sources:
        for entry_match in entry_pattern.finditer(source):
            entry_opening = source.find("{", entry_match.start())
            entry_end = matching_brace(source, entry_opening)
            if entry_end is not None and route_pattern.search(source, entry_match.start(), entry_end + 1):
                bound = True
                break
        if bound:
            break
    if not bound:
        raise SystemExit(
            f"instrumentation-coverage: route for {name} has no owner-bound production route call "
            f"in {route['owner']}.{route['entry']}"
        )
    if route["allowedHarness"] not in {"process", "component"}:
        raise SystemExit(f"instrumentation-coverage: route for {name} has unknown harness")

exemptions = {}
for line in exemptions_path.read_text(encoding="utf-8").splitlines():
    match = re.match(r"^\| `([A-Za-z_]\w*)` \| (.+?) \| (.+?) \|$", line)
    if match:
        name, reason, removal = match.groups()
        if name in exemptions:
            raise SystemExit(f"instrumentation-coverage: duplicate exemption {name}")
        exemptions[name] = (reason, removal)
unknown_exemptions = set(exemptions) - cases
if unknown_exemptions:
    raise SystemExit(f"instrumentation-coverage: exemptions name unknown cases: {sorted(unknown_exemptions)}")

files = []
for directory in log_dirs:
    if not directory.exists():
        raise SystemExit(f"instrumentation-coverage: missing log directory {directory}")
    if directory.is_file() and directory.suffix == ".jsonl":
        files.append(directory)
    else:
        files.extend(sorted(directory.glob("**/*.jsonl")))
if not files:
    raise SystemExit("instrumentation-coverage: supplied logs contain no JSON Lines files")

emitted = set()
origins = set()
observed_harnesses = {name: set() for name in routes}
known_origins = {"productionRoute", "encodingProbe", "gateFixture"}
for file in files:
    for line_number, line in enumerate(file.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            raise SystemExit(f"instrumentation-coverage: invalid JSON in {file}:{line_number}: {error}")
        event = record.get("ev")
        if event is not None:
            origin = record.get("origin")
            if event not in {"runStart", "runEnd", "repeated", "sizeLimitReached", "mainActorStall"}:
                if origin not in known_origins:
                    raise SystemExit(f"instrumentation-coverage: event {event} has missing or unknown evidence origin")
                origins.add(origin)
                if origin == "productionRoute":
                    if record.get("channel") != "productionRoutePipe":
                        raise SystemExit(
                            f"instrumentation-coverage: production event {event} is not from the "
                            "gate-owned evidence channel"
                        )
                    route_name = record.get("route")
                    if route_name != event:
                        raise SystemExit(
                            f"instrumentation-coverage: production event {event} has route {route_name!r}"
                        )
                    emitted.add(event)
                    harness = record.get("harness")
                    if harness not in {"process", "component"}:
                        raise SystemExit(
                            f"instrumentation-coverage: production event {event} has missing or unknown harness"
                        )
                    # Component runs may exercise a route that is process-only in the final
                    # evidence contract. They must not count toward that contract, but their
                    # presence is not itself invalid; the process harness must still be observed.
                    if routes.get(event, {}).get("allowedHarness") == "process" and harness != "process":
                        continue
                    observed_harnesses.setdefault(event, set()).add(harness)
if not emitted:
    raise SystemExit("instrumentation-coverage: logs emitted zero event names")

log_owned = {"runStart", "runEnd", "repeated", "sizeLimitReached", "mainActorStall"}
unknown = emitted - cases - log_owned
if unknown:
    raise SystemExit(f"instrumentation-coverage: log contains names outside EditorTraceEvent: {sorted(unknown)}")
for name in sorted(emitted):
    if name in routes and routes[name]["allowedHarness"] not in observed_harnesses.get(name, set()):
        raise SystemExit(
            f"instrumentation-coverage: event {name} was not observed in its allowed "
            f"{routes[name]['allowedHarness']} harness"
        )

missing = cases - emitted - set(exemptions)
if missing:
    for name in sorted(missing):
        print(f"instrumentation-coverage: event absent from observed logs: {name}", file=sys.stderr)
    raise SystemExit(f"instrumentation-coverage: FAILED ({len(missing)} missing event(s))")
overlap = cases & emitted & set(exemptions)
if overlap:
    raise SystemExit(f"instrumentation-coverage: case is both emitted and exempted: {sorted(overlap)}")

covered = cases & emitted
print(f"instrumentation-coverage: PASS ({len(covered)} emitted, {len(exemptions)} reviewed exemption(s))")
for name, (_, removal) in sorted(exemptions.items()):
    if name not in emitted:
        print(f"instrumentation-coverage: exempted {name} — {removal}")
PY
