#!/bin/bash
# REQ-099/135: trace vocabulary coverage is proved by emitted JSON Lines, not source text.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cases_file="$repo_root/Markdown Editor/EditorTrace.swift"
exemptions_file="$repo_root/docs/trace-coverage-exemptions.md"
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

python3 - "$cases_file" "$exemptions_file" "${log_dirs[@]}" <<'PY'
import json
import pathlib
import re
import sys

cases_path = pathlib.Path(sys.argv[1])
exemptions_path = pathlib.Path(sys.argv[2])
log_dirs = [pathlib.Path(value) for value in sys.argv[3:]]

if not cases_path.is_file():
    raise SystemExit(f"instrumentation-coverage: missing case source {cases_path}")
if not exemptions_path.is_file():
    raise SystemExit(f"instrumentation-coverage: missing exemption record {exemptions_path}")

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
            emitted.add(event)
if not emitted:
    raise SystemExit("instrumentation-coverage: logs emitted zero event names")

log_owned = {"runStart", "runEnd", "repeated", "sizeLimitReached", "mainActorStall"}
unknown = emitted - cases - log_owned
if unknown:
    raise SystemExit(f"instrumentation-coverage: log contains names outside EditorTraceEvent: {sorted(unknown)}")

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
