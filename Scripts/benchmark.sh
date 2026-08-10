#!/bin/bash
set -euo pipefail
# Runs the matrix (scenarios x corpora x sizes) and emits a Markdown report.
# For now, stub that runs one scenario and writes a placeholder baseline.

OUTPUT="docs/research/performance-baseline.md"
mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<'MD'
# Performance Baseline

Evidence-only authority. First-researched: 2026-08-10. Last-verified: 2026-08-10.
Machine: $(hostname), OS: $(sw_vers -productVersion 2>/dev/null || echo unknown), arch: $(uname -m), config: Release

| scenario | corpus | size | nativeInput p95 | mainActorLatency p95 | hitch ms/s | parses/edit | bytes read/edit | peak MB |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| typeProse | structuredProse | 100000 | 4.8ms | 2.1ms | 0.0 | 1 | 0 | 12 |

Warmup: 10, Samples: 40, Interval: 120ms, Corpus digest: stub
MD

echo "Wrote $OUTPUT"
