# COR-60 — Measurements carry their provenance

- **Status:** Approved; not implemented
- **Requirements:** REQ-137 (new, `Planned`); REQ-090, REQ-128 unchanged in intent
- **ARC invariants:** ARC-027 (strengthened); ARC-Q05 unchanged

## Context

`Scripts/benchmark.sh`, as committed on 2026-08-10, writes `docs/research/performance-baseline.md`
from a heredoc with a **quoted** delimiter:

```bash
cat > "$OUTPUT" <<'MD'
Machine: $(hostname), OS: $(sw_vers -productVersion 2>/dev/null || echo unknown), arch: $(uname -m)
| typeProse | structuredProse | 100000 | 4.8ms | 2.1ms | 0.0 | 1 | 0 | 12 |
MD
```

Quoting the delimiter suppresses expansion, so the provenance line reaches the file as literal
`$(hostname)` text, beneath a hardcoded results row. The script's own comment calls it a placeholder.
Had it been committed, `docs/research/` would hold a file whose numbers were never measured, carrying
the evidence-only authority header that `check-documentation-authority.sh` requires of research.

This is the same class as the two above, in the measurement layer: the artefact *looks like* a
measurement, and nothing checks that a measurement occurred. `CLAUDE.md` §4 already records the
adjacent lesson — REQ-090's p95 was real but measured on `String(repeating: "word ", count: 20_000)`,
a document with no newline, heading, list or table. That rule says *a proof's inputs are part of the
proof*. This one adds: **a proof's provenance is part of the proof.**

## Architecture impact

`ARC-027` strengthened into the measurement layer. No application code beyond the benchmark driver
that COR-45 re-introduces when it re-runs.

## Production changes

### 1. Baselines are machine-written only

`Scripts/benchmark.sh` emits every field from the run — never from a literal. The provenance block
carries host, `sw_vers` product version and build, `uname -m`, configuration, Xcode version, the
corpus digest, warmup and sample counts, the sampling interval, the commit SHA, and a run id.
Regenerating the file must be the only way to change a number in it.

### 2. `Scripts/check-measurement-provenance.sh` — new

For every file under `docs/research/` containing a results table:

1. reject any unexpanded shell construct — `$(`, `${`, a bare `` ` `` — anywhere in the file. This
   single rule catches the 2026-08-10 defect outright;
2. require a complete provenance block with every field above populated and non-placeholder;
3. require the recorded commit SHA to exist in the repository;
4. require the corpus digest to match the digest the current `PerformanceCorpus` produces, so a
   baseline measured against a corpus that has since changed shape is stale by construction rather
   than by anyone noticing;
5. fail closed on a results table with no provenance block.

### 3. Baseline comparison

`benchmark.sh --check` re-runs the matrix and compares against the committed baseline within a
declared tolerance, failing on regression beyond it. This is what makes a fabricated baseline
self-defeating: invented numbers are contradicted by the first honest run rather than becoming the
reference everything is measured against.

Tolerance is declared in the baseline itself, per metric, so tightening it is a reviewed edit.

## Phases

1. Rewrite `benchmark.sh` emission with full provenance. (Ordering note: this increment lands
   *after* COR-45 has re-run, since COR-45 owns `BenchmarkDriver` and `PerformanceCorpus`. Until
   then, §2's gate stands alone and guards `docs/research/` against hand-written numbers.)
2. `check-measurement-provenance.sh` plus fixtures; wire into `fast-check.sh`.
3. `--check` comparison mode and the recorded tolerance.

## Automated proof

`Scripts/test-check-measurement-provenance.sh` (new, fixture-based):

- a fixture containing literal `$(hostname)` → fail (the exact 2026-08-10 artefact);
- a results table with no provenance block → fail;
- a provenance block with an empty or `stub` field → fail;
- a recorded SHA absent from the repository → fail;
- a corpus digest that does not match the current corpus → fail;
- a complete, self-consistent fixture → **pass** (liveness);
- a research file with no results table → pass, unexamined.

**Rehearsal (`CLAUDE.md` §9):** run the gate against the `performance-baseline.md` that
`Scripts/benchmark.sh` produced at `4803d25`. It must fail on rules 1 and 2 before this increment is
trusted.

## Instrumentation and performance evidence

The gate is a text check over `docs/research/`, costing milliseconds. `--check` costs a full
benchmark matrix and therefore belongs to the closing sequence, not to `fast-check.sh`.

## Failure and rollback

Rule 4 — corpus digest matching — will invalidate the baseline whenever the corpus legitimately
changes shape. That is intended and it is a cost: a corpus change forces a re-measurement. If it
proves too coarse in practice (for example, adding a seventh corpus shape invalidating the six
existing rows), refine the digest to be per-shape rather than whole-enumeration. Record the change;
do not weaken the rule to "warn".

## Deletion and conformance gate

- No committed measurement in `docs/research/` is hand-written; each carries a complete provenance
  block.
- `benchmark.sh` contains no literal result value and no quoted heredoc emitting provenance.
- The gate is wired into `fast-check.sh` and the closing sequence, and its fixtures run there too.
