#!/bin/bash
# REQ-128: run the shipping binary and write an evidence-only performance baseline.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
derived="${BENCHMARK_DERIVED_DATA:-$repo_root/.benchmark-build}"
output="${BENCHMARK_OUTPUT:-$repo_root/docs/research/performance-baseline.md}"
duration="${BENCHMARK_DURATION_SECONDS:-2}"
sizes=(10000 100000)
if [[ -n "${BENCHMARK_SIZES:-}" ]]; then read -r -a sizes <<<"$BENCHMARK_SIZES"; fi

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
metadata="$run_root/runs.tsv"
: >"$metadata"

make_fixture() {
    local corpus="$1" target="$2" size="$3" unit
    case "$corpus" in
        degenerateParagraph) unit='word ' ;;
        structuredProse) unit=$'## Heading\n\nParagraph with **strong**, *emphasis*, `code` and [link](https://example.com).\n\n' ;;
        heavyLists) unit=$'- item\n  - nested\n    - deeper\n- [ ] task\n1. ordered\n\n' ;;
        tableDense) unit=$'| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n\n' ;;
        codeHeavy) unit=$'```swift\nlet x = 1\nlet y = 2\nlet z = x + y\n```\n\n' ;;
        imageHeavy) unit=$'![alt](assets/sample.png)\n\nParagraph.\n\n' ;;
        *) echo "benchmark: unknown corpus $corpus" >&2; return 1 ;;
    esac
    python3 - "$unit" "$target" "$size" <<'PY'
import pathlib
import sys

unit, target, size = sys.argv[1], pathlib.Path(sys.argv[2]), int(sys.argv[3])
encoded = unit.encode("utf-8")
if not encoded:
    raise SystemExit("benchmark: corpus unit must not be empty")
repetitions = (size + len(encoded) - 1) // len(encoded)
payload = encoded * repetitions
while len(payload) > size and payload.endswith(encoded):
    payload = payload[:-len(encoded)]
target.write_bytes(payload)
PY
}

for scenario in typeProse typeInTable typeAdjacentMarkup applyCommands toggleModes scrollDocument undoRedoStorm openAndIdle soak; do
    for corpus in degenerateParagraph structuredProse heavyLists tableDense codeHeavy imageHeavy; do
        for size in "${sizes[@]}"; do
            run_id="${scenario}-${corpus}-${size}"
            run_dir="$run_root/$run_id"
            mkdir -p "$run_dir/logs"
            fixture="$run_dir/fixture.md"
            make_fixture "$corpus" "$fixture" "$size"
            if [[ "$corpus" == imageHeavy ]]; then
                mkdir -p "$run_dir/assets"
                cp "$repo_root/Scripts/Fixtures/assets/sample.png" "$run_dir/assets/sample.png"
            fi
            MARKDOWN_EDITOR_DIAGNOSTICS_DIR="$run_dir/logs" \
            MARKDOWN_EDITOR_FRAME_OBSERVER=1 \
                "$binary" --benchmark "$scenario" --corpus "$corpus" --size "$size" \
                --duration "$duration" --interval-ms 120 \
                -ApplePersistenceIgnoreState YES "$fixture" >/dev/null 2>&1
            log="$(find "$run_dir/logs" -name '*.jsonl' -type f -print -quit)"
            [[ -n "$log" ]] || { echo "benchmark: no diagnostic log for $run_id" >&2; exit 1; }
            python3 "$repo_root/Scripts/verify-smoke-log.py" "$log" 100 \
                --label "benchmark:$run_id" --fail-on-budget-exceeded >/dev/null
            printf '%s\t%s\t%s\t%s\n' "$scenario" "$corpus" "$size" "$log" >>"$metadata"
        done
    done
done

python3 - "$metadata" "$output" "$repo_root" <<'PY'
import datetime as dt
import hashlib
import json
import os
import pathlib
import platform
import subprocess
import sys
import uuid

metadata = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
repo = pathlib.Path(sys.argv[3])

def value(data, key):
    return data.get("data", {}).get(key)

rows = []
sample_counts = []
for line in metadata.read_text().splitlines():
    scenario, corpus, size, path = line.split("\t")
    records = [json.loads(item) for item in pathlib.Path(path).read_text().splitlines() if item.strip()]
    summaries = {
        value(record, "metric"): value(record, "p95Nanos")
        for record in records if record.get("ev") == "performanceSummary"
    }
    sample_counts.extend(
        value(record, "count") or 0
        for record in records if record.get("ev") == "performanceSummary"
    )
    ledgers = [record for record in records if record.get("ev") == "workLedger"]
    frames = next((record for record in records if record.get("ev") == "frameStatistics"), {})
    memories = [record for record in records if record.get("ev") == "memoryFootprint"]
    if not records or not any(record.get("ev") == "runEnd" for record in records):
        raise SystemExit(f"benchmark: unclean run for {scenario}/{corpus}/{size}")
    parse_count = sum(value(record, "documentParses") or 0 for record in ledgers)
    bytes_read = sum(value(record, "fileBytesRead") or 0 for record in ledgers)
    peak = max((value(record, "peakBytes") or 0 for record in memories), default=0)
    def millis(nanos):
        return "n/a" if nanos is None else f"{nanos / 1_000_000:.3f} ms"
    rows.append((scenario, corpus, size, millis(summaries.get("nativeInputCallback")),
                 millis(summaries.get("mainActorLatency")), value(frames, "hitchMillisPerSecond") or "n/a",
                 parse_count, bytes_read, f"{peak / 1_048_576:.2f}" if peak else "n/a"))

corpus_source = repo / "Markdown Editor/PerformanceCorpus.swift"
digest = hashlib.sha256(corpus_source.read_bytes()).hexdigest()
now = dt.date.today().isoformat()
def command(*args, fallback="unavailable"):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip() or fallback
    except (OSError, subprocess.CalledProcessError):
        return fallback
os_version = command("sw_vers", "-productVersion")
os_build = command("sw_vers", "-buildVersion")
xcode = command("xcodebuild", "-version").replace("\n", "; ")
commit = command("git", "rev-parse", "HEAD")
run_id = str(uuid.uuid4())
sample_count = sum(sample_counts)
output.parent.mkdir(parents=True, exist_ok=True)
with output.open("w", encoding="utf-8") as handle:
    handle.write("# Performance baseline\n\n")
    handle.write("- **Authority:** Evidence only\n")
    handle.write("- **First researched:** %s\n" % now)
    handle.write("- **Last verified:** %s\n" % now)
    handle.write("- **Refresh when:** app, OS, architecture, corpus, scenario, or benchmark-driver changes.\n")
    handle.write("Host: %s\n" % platform.node())
    handle.write("OS: macOS %s\n" % os_version)
    handle.write("OS build: %s\n" % os_build)
    handle.write("Architecture: %s\n" % platform.machine())
    handle.write("Configuration: Release\n")
    handle.write("Xcode: %s\n" % xcode)
    handle.write("Corpus digest: %s\n" % digest)
    handle.write("Warmup: 1 s\n")
    handle.write("Samples: %s\n" % sample_count)
    handle.write("Interval: 120 ms\n")
    handle.write("Commit: %s\n" % commit)
    handle.write("Run ID: %s\n\n" % run_id)
    handle.write("| scenario | corpus | size | nativeInput p95 | mainActorLatency p95 | hitch ms/s | parses | bytes read | peak MB |\n")
    handle.write("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n")
    for row in rows:
        handle.write("| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n" % row)
PY

echo "benchmark: wrote $output"
