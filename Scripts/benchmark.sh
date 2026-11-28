#!/bin/bash
# REQ-128: run the shipping Release binary through the Swift-owned benchmark matrix.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
derived="${BENCHMARK_DERIVED_DATA:-$repo_root/.benchmark-build}"
output="${BENCHMARK_OUTPUT:-$repo_root/docs/research/2026-08-21-performance-baseline.md}"
duration="${BENCHMARK_DURATION_SECONDS:-2}"
interval_ms="${BENCHMARK_INTERVAL_MS:-120}"
sizes="${BENCHMARK_SIZES:-10000 100000}"

xcodebuild build \
    -project "Markdown Editor.xcodeproj" \
    -scheme "Markdown Editor" \
    -configuration Release \
    -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' >/dev/null

binary="$derived/Build/Products/Release/Markdown Editor.app/Contents/MacOS/Markdown Editor"
[[ -x "$binary" ]] || { echo "benchmark: missing Release binary $binary" >&2; exit 1; }

run_root="$(mktemp -d "${TMPDIR:-/tmp}/markdown-editor-benchmark.XXXXXX")"
trap 'rm -rf "$run_root"' EXIT
results="$run_root/results"
logs="$run_root/logs"
mkdir -p "$results" "$logs" "$run_root/assets"
cp "$repo_root/Scripts/Fixtures/assets/sample.png" "$run_root/assets/sample.png"
fixture="$run_root/fixture.md"
touch "$fixture"
manifest="$run_root/manifest.json"

BENCHMARK_DURATION_SECONDS="$duration" BENCHMARK_INTERVAL_MS="$interval_ms" \
BENCHMARK_SIZES="$sizes" BENCHMARK_RESULT_DIRECTORY="$results" \
python3 - "$manifest" <<'PY'
import json
import os
import pathlib
import sys

sizes = [int(item) for item in os.environ.get("BENCHMARK_SIZES", "10000 100000").split()]
if not sizes or any(size <= 0 for size in sizes):
    raise SystemExit("benchmark: BENCHMARK_SIZES must contain positive integers")
pathlib.Path(sys.argv[1]).write_text(json.dumps({
    "durationSeconds": float(os.environ.get("BENCHMARK_DURATION_SECONDS", "2")),
    "intervalMillis": float(os.environ.get("BENCHMARK_INTERVAL_MS", "120")),
    "sizes": sizes,
    "resultDirectory": str(pathlib.Path(os.environ["BENCHMARK_RESULT_DIRECTORY"]).resolve()),
}), encoding="utf-8")
PY

MARKDOWN_EDITOR_DIAGNOSTICS_DIR="$logs" MARKDOWN_EDITOR_FRAME_OBSERVER=1 MARKDOWN_EDITOR_BENCHMARK=1 \
    "$binary" --benchmark-manifest "$manifest" \
    -ApplePersistenceIgnoreState YES "$fixture" >/dev/null 2>&1

log="$(find "$logs" -name '*.jsonl' -type f -print -quit)"
[[ -n "$log" ]] || { echo "benchmark: no diagnostic log" >&2; exit 1; }
python3 - "$results" "$log" <<'PY'
import json
import pathlib
import sys

result_dir, log_path = map(pathlib.Path, sys.argv[1:3])
results = sorted(path for path in result_dir.glob("*.json") if path.name != "benchmark-summary.json")
if not results:
    raise SystemExit("benchmark: driver emitted no case results")
seen = set()
for path in results:
    value = json.loads(path.read_text(encoding="utf-8"))
    key = (value["scenario"], value["corpus"], value["size"])
    if key in seen:
        raise SystemExit(f"benchmark: duplicate case result {key}")
    seen.add(key)
    if not value["passed"] or value["progress"] <= 0:
        raise SystemExit(f"benchmark: failed case {key}: {value}")
    if value["timeoutCount"] or value["unknownActionCount"] or value["duplicateSampleCount"]:
        raise SystemExit(f"benchmark: invalid outcome accounting for {key}")
    outcomes = value.get("actionOutcomes")
    if not isinstance(outcomes, list) or len(outcomes) != value["actionAttempts"]:
        raise SystemExit(f"benchmark: missing per-action outcome contract for {key}: {value}")
    if value.get("actionContractFailureCount", 0) != 0:
        raise SystemExit(f"benchmark: unexpected action outcome for {key}: {value}")
    for outcome in outcomes:
        if not outcome.get("action") or outcome.get("expected") != outcome.get("observed"):
            raise SystemExit(f"benchmark: action contract mismatch for {key}: {outcome}")
    if value["actionAttempts"] < value["expectedActionAttemptsMinimum"]:
        raise SystemExit(f"benchmark: action contract not exercised for {key}: {value}")
    if value["progress"] < value["expectedProgressMinimum"]:
        raise SystemExit(f"benchmark: progress contract not exercised for {key}: {value}")
summary_path = result_dir / "benchmark-summary.json"
if not summary_path.is_file():
    raise SystemExit("benchmark: driver emitted no exact matrix summary")
summary = json.loads(summary_path.read_text(encoding="utf-8"))
def key_of(item):
    return (item["scenario"], item["corpus"], item["size"])
expected = [key_of(item) for item in summary["expectedCases"]]
completed = [key_of(item) for item in summary["completedCases"]]
if len(expected) != 108:
    raise SystemExit(f"benchmark: Swift driver expected {len(expected)} cases; exact matrix requires 108")
if sorted(expected) != sorted(completed) or sorted(expected) != sorted(seen):
    raise SystemExit("benchmark: result set does not exactly match the Swift-owned matrix")
source_shapes = {}
for path in results:
    value = json.loads(path.read_text(encoding="utf-8"))
    shape = (value["corpus"], value["size"])
    metrics = {item["name"]: item for item in value.get("metrics", [])}
    source = metrics.get("sourceHighlightCompute")
    if source and source.get("count", 0) >= 1 and source.get("p95Nanos", 0) > 0:
        source_shapes[shape] = source
expected_shapes = {(corpus, size) for corpus in {item["corpus"] for item in summary["expectedCases"]} for size in {item["size"] for item in summary["expectedCases"]}}
missing_shapes = sorted(expected_shapes - source_shapes.keys())
if missing_shapes:
    raise SystemExit(f"benchmark: missing sourceHighlightCompute evidence for corpus shapes {missing_shapes}")
records = [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines() if line.strip()]
if not any(record.get("ev") == "runEnd" for record in records):
    raise SystemExit("benchmark: diagnostic run did not terminate cleanly")
if not any(record.get("ev") == "workLedger" for record in records):
    raise SystemExit("benchmark: no intent ledger evidence")
PY

python3 - "$results" "$log" "$output" "$repo_root" "$duration" "$interval_ms" <<'PY'
import datetime as dt
import hashlib
import json
import os
import pathlib
import platform
import subprocess
import sys
import tempfile
import uuid

results_dir, log_path, output_path, repo = map(pathlib.Path, sys.argv[1:5])
duration, interval = sys.argv[5:7]

def command(*args, fallback="unavailable"):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip() or fallback
    except (OSError, subprocess.CalledProcessError):
        return fallback

rows = []
for path in sorted(path for path in results_dir.glob("*.json") if path.name != "benchmark-summary.json"):
    value = json.loads(path.read_text(encoding="utf-8"))
    metrics = {item["name"]: item for item in value.get("metrics", [])}
    parse = metrics.get("parseProjection", {})
    source = metrics.get("sourceHighlightCompute", {})
    rows.append((value["scenario"], value["corpus"], value["size"], parse.get("p95Nanos", "n/a"),
                 source.get("p95Nanos", "n/a"),
                 parse.get("budgetExceeded", "n/a"), source.get("budgetExceeded", "n/a"),
                 value["actionAttempts"], value["accepted"], value["refused"], value["progress"]))
records = [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines() if line.strip()]
frame = next((record.get("data", {}) for record in records if record.get("ev") == "frameStatistics"), {})
digest_input = (repo / "Markdown Editor/PerformanceCorpus.swift").read_bytes() + b"\n-- benchmark action authority --\n" + (repo / "Markdown Editor/BenchmarkDriver.swift").read_bytes()
digest = hashlib.sha256(digest_input).hexdigest()
implementation_paths = [
    "Markdown Editor/PerformanceCorpus.swift",
    "Markdown Editor/BenchmarkDriver.swift",
    "Markdown Editor/IncrementalSourceHighlighter.swift",
    "Markdown Editor/SourceEditor.swift",
    "Markdown Editor/PerformanceSampler.swift",
]
implementation_input = b""
for relative in implementation_paths:
    implementation_input += relative.encode() + b"\n" + (repo / relative).read_bytes() + b"\n-- source implementation authority --\n"
implementation_digest = hashlib.sha256(implementation_input).hexdigest()
now = dt.date.today().isoformat()
text = ["# Performance baseline\n\n", "- **Authority:** Evidence only\n", f"- **First researched:** {now}\n",
        f"- **Last verified:** {now}\n", "- **Refresh when:** app, OS, architecture, corpus, scenario, or benchmark-driver changes.\n",
        f"Machine: {command('sysctl', '-n', 'hw.model')}\n", f"OS: macOS {command('sw_vers', '-productVersion')}\n",
        f"OS build: {command('sw_vers', '-buildVersion')}\n", f"Architecture: {platform.machine()}\n",
        "Configuration: Release\n", f"Xcode: {command('xcodebuild', '-version').replace(chr(10), '; ')}\n",
        f"Corpus digest: {digest}\n", "Corpus/action authority: PerformanceCorpus.swift and BenchmarkDriver.swift\n",
        f"Source implementation digest: {implementation_digest}\n", "Source implementation authority: PerformanceCorpus.swift, BenchmarkDriver.swift, IncrementalSourceHighlighter.swift, SourceEditor.swift, and PerformanceSampler.swift\n",
        "Method: Scripts/benchmark.sh builds the Release binary, passes a parameter-only manifest, and verifies the exact Swift-owned 6 x 2 x 9 matrix plus per-case action contracts.\n",
        "Warmup: 1.5 s per case\n", f"Duration: {duration} s per case\n", f"Interval: {interval} ms\n",
        f"Samples: {len(rows)} case results\n", f"Frame hitch ms/s: {frame.get('hitchMillisPerSecond', 'n/a')}\n",
        f"Commit: {command('git', 'rev-parse', 'HEAD')}\n", f"Run ID: {uuid.uuid4()}\n\n",
        "| scenario | corpus | size | parseProjection p95 ns | sourceHighlightCompute p95 ns | parse budget exceeded | source budget exceeded | actions | accepted | refused | progress |\n",
        "| --- | --- | ---: | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: |\n"]
text.extend("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n" % row for row in rows)
output = pathlib.Path(output_path)
output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=output.parent, delete=False) as handle:
    handle.write("".join(text))
    temporary = pathlib.Path(handle.name)
os.replace(temporary, output)
PY

echo "benchmark: wrote $output"
