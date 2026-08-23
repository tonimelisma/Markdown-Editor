# Semantic command main-actor cost

- **Authority:** evidence only. Not a product decision and not a repair plan. The repairs it
  motivates are `docs/plans/COR-86…COR-90`.
- **First researched:** 2026-08-22
- **Last verified:** 2026-08-22
- **Environment:** macOS 27.0 (build 26A5416b), Darwin 27.0.0, arm64. Xcode 27.0 (27A5228h).
  Phase tables are **Debug, `-Onone`**. The end-to-end table is **Release**, taken after COR-86
  restored `ENABLE_TESTABILITY` for that configuration.
- **Method:** a temporary probe test, since deleted, called the production entry points directly
  on the main actor over every `PerformanceCorpus` case at its default 100,000-UTF-16 target.
  One warm-up parse, then 5 recorded iterations per case, each with a distinct `sourceVersion` and
  snapshot ID so no cache could serve a repeat. Timing by `DispatchTime.now().uptimeNanoseconds`
  around each phase individually. Reproduce by re-creating a probe that calls, in order:
  `MarkdownSourceIndex(source:sourceVersion:)`, `MarkdownParser.parse(_:sourceVersion:intent:)`,
  `MarkdownProjectionModel.build(tree:index:intent:)`,
  `PresentationSnapshot.from(model:id:locationGeneration:sourceText:)`, and
  `ProjectionOracle.validate(snapshot:)`.
- **Refresh triggers:** any change to `ProjectionOracle`, `PresentationSnapshot.make`,
  `ProjectionAtom.from`, `MarkdownProjectionModel.build`, or the pinned cmark-gfm revision; and
  the first Release run once `ENABLE_TESTABILITY` is restored (COR-86).

## Why this was measured

`EditorSession` routes every semantic formatting command — bold, italic, heading, list, quote,
code block, link — through `EditorSemanticWorker.sync`, which dispatches to a serial queue and
**waits on a `DispatchSemaphore` from the main thread**. Inside that wait,
`SemanticEditEngine.planAuthoritativeTransition` calls `AuthoritativePresentationBuilder.build`,
which performs a complete source index, cmark parse, projection model build, and presentation
snapshot construction **for the whole document**.

The elapsed time is added to `WorkLedger.mainThreadBlockedNanos`, serialized by
`JSONLinesEditorTrace`, and written to every run log. Nothing in the repository asserts a bound on
it, and `PerformanceSampler.Metric` — the closed set `PerformanceBudgetTests.everyMetricHasABudget`
iterates — has no case for it. So the quantity was recorded but never known.

## What was found

### Phase breakdown of one authoritative rebuild

Milliseconds, mean of 5 iterations, Debug `-Onone`.

| corpus | blocks | source index | cmark parse | projection model | snapshot | **total** |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| degenerateParagraph | 1 | 1.7 | 4.4 | 0.0 | 15.8 | **21.9** |
| codeHeavy | 2,084 | 2.0 | 4.9 | 7.0 | 17.2 | **31.0** |
| imageHeavy | 7,695 | 2.0 | 13.8 | 16.4 | 33.7 | **65.8** |
| structuredProse | 2,174 | 1.9 | 17.6 | 19.9 | 44.0 | **83.5** |
| tableDense | 24,400 | 2.0 | 44.9 | 52.1 | 77.4 | **176.3** |
| heavyLists | 18,520 | 1.9 | 27.5 | 53.3 | 98.5 | **181.3** |

An end-to-end probe of `AuthoritativePresentationBuilder.build` itself, run separately, agreed:
p50 22.0 / 31.2 / 66.4 / 79.3 / 181.6 / 182.8 ms in the same corpus order, max 192.0 ms.

### Sub-phase breakdown inside `PresentationSnapshot.make`

| corpus | atoms | `ProjectionAtom.from` | `toSegments` | coordinate map | **`ProjectionOracle.validate`** |
| --- | ---: | ---: | ---: | ---: | ---: |
| degenerateParagraph | 2 | 0.0 | 0.0 | 0.0 | **22.1** |
| codeHeavy | 2,084 | 2.5 | 0.3 | 0.0 | **20.5** |
| imageHeavy | 10,260 | 9.6 | 1.5 | 0.0 | **33.5** |
| structuredProse | 13,044 | 10.2 | 1.8 | 0.0 | **44.8** |
| tableDense | 29,280 | 18.3 | 4.2 | 0.0 | **80.9** |
| heavyLists | 29,632 | 26.7 | 4.3 | 0.0 | **95.1** |

### Finding 1 — the oracle costs more than the parse it validates *in Debug*

`ProjectionOracle.validate` is the largest single cost in a formatting command **as measured in
Debug**, and on every corpus case it exceeds the cmark parse whose output it checks — 95.1 ms
against 27.5 ms on `heavyLists`, a factor of 3.5.

> **Corrected 2026-08-22, after COR-88 shipped.** This finding does not transfer to Release, and
> the heading originally claimed it without qualification. Replacing the coverage array improved
> Release worst-case cost by 0–25 % on the structured corpora, not the ~50 % this table implies —
> see Finding 6. The array's per-character loop is dominated by bounds-checking and retain/release
> that `-Onone` keeps and `-O` largely removes. **A phase breakdown taken in Debug attributes cost
> to whatever `-Onone` punishes most, which is not what the user pays for.** The repair was still
> correct and was kept, but on the strength of Finding 2, not this one.

### Finding 2 — the oracle's cost is driven by document length, not by segment count

`degenerateParagraph` is one block and two segments, and validating it costs 22.1 ms. The cause is
in `ProjectionOracle.validate`:

```swift
var covered = Array(repeating: 0, count: max(renderedCount, 0))
…
for i in 0..<range.length {
    let idx = range.location + i
    covered[idx] += 1
    if covered[idx] > 1 { return .failure(Failure(code: "overlap", …)) }
}
if let gap = covered.firstIndex(where: { $0 == 0 }), renderedCount > 0 { … }
```

On a 100,000-character document this allocates an 800 KB array and performs 100,000
bounds-checked increments to establish a property about a few thousand segment boundaries. The
property — *the segments exactly partition the projection* — is a statement about boundaries, and
is decidable in O(segments) by checking that the segments tile: first starts at 0, each starts
where the previous ended, last ends at `renderedCount`.

That formulation also decides **ordering**, which the coverage array cannot see. It is therefore
a strictly stronger proof at roughly 1 % of the cost. This is measured as a property of the
current formulation, not as a proposal; the proposal is COR-88.

### Finding 3 — segments are round-tripped through atoms and back

`PresentationSnapshot.from` calls `ProjectionAtom.from(segments:sourceText:renderedText:)`, and
`PresentationSnapshot.make` immediately calls `ProjectionAtom.toSegments(atoms)` to reconstruct
what its caller already held. Measured at 0.3–4.3 ms per rebuild. `make` also constructs the full
`PresentationSnapshot` value twice — once as `candidate` for the oracle, then again field-by-field
to set `oracleValid`.

### Finding 4 — the remaining cost is whole-document work for a one-block change

With the oracle and the round-trip removed, the residue is genuine computation: cmark parse
(4.4–44.9 ms), projection model build (0.0–53.3 ms), atom construction (0.0–26.7 ms). All of it is
whole-document, for a command that changes one block. On `heavyLists`, 18,519 of 18,520 blocks are
byte-identical before and after, differing only by a fixed offset.

### Finding 4a — the Release figure, measured end-to-end (added 2026-08-22, after COR-86)

`SemanticCommandBudgetTests.semanticCommandStaysWithinBudget` drives `.bold` through the
production `EditorCommandController` route — planning, reduction, commit, presentation install —
on a document consisting of one ordinary lead paragraph followed by the corpus. Eight measured
commands after one warm-up, each asserted `accepted`, p95 of the `semanticCommand` metric:

| corpus | Release p95 | verdict against the 16 ms budget |
| --- | ---: | --- |
| degenerateParagraph | within budget | pass |
| codeHeavy | 17.8 ms | fail |
| imageHeavy | 37.2 ms | fail |
| structuredProse | 42.2 ms | fail |
| heavyLists | 103.0 ms | fail |
| tableDense | 145.6 ms | fail |

**Release optimization buys far less here than expected** — roughly 1.2–1.7× against the Debug
phase totals, not the 3–5× assumed when this document was first written. The cost is dominated by
work `-O` does not help much with: cmark's own C, allocation, and reference counting.

A first version of this test selected a zero-length caret and passed on all six cases. `.bold`
refuses an empty selection, so it was measuring refusals. The test now asserts every measured
command returned `.accepted`, and the corpus-independent lead paragraph exists so that the
selection is identical across shapes on which `.bold` would otherwise legitimately refuse. Noted
because the vacuous version was green and looked like good news.

**Consequence for COR-89.** Its decision gate is expected to open. Even if COR-88 removes the
oracle entirely — roughly half the rebuild cost — `tableDense` and `heavyLists` remain far above
16 ms.

### Finding 6 — what COR-88 actually bought (measured 2026-08-22, after the repair)

Worst of three commands through the production route, same fixture as Finding 4a.

| corpus | Release before | Release after | Debug after |
| --- | ---: | ---: | ---: |
| degenerateParagraph | ~16 ms | **7.7 ms** | 26.1 ms |
| codeHeavy | 17.8 ms | 16.4 ms | 68.9 ms |
| structuredProse | 42.2 ms | 41.7 ms | 235.1 ms |
| imageHeavy | 37.2 ms | 41.2 ms | 247.3 ms |
| heavyLists | 103.0 ms | 92.3 ms | 559.3 ms |
| tableDense | 145.6 ms | **109.0 ms** | 650.2 ms |

`degenerateParagraph` — one block, two segments, 100,000 characters — halved, which is the
signature of a length-driven cost being removed and is exactly what Finding 2 predicted. The
structured corpora improved 0–25 %; `imageHeavy` moved within noise.

**Two consequences.**

1. The remaining cost is the parse, the projection model build, and atom construction, all
   whole-document. COR-89's decision gate is **open**: `tableDense` at 109 ms and `heavyLists` at
   92 ms are far from the 16 ms budget, and no amount of tightening inside the snapshot will
   close that.
2. **Two micro-optimisations named in COR-88's plan were not made.** The `ProjectionAtom.from` →
   `toSegments` round-trip and the double `PresentationSnapshot` construction were justified by
   the Debug sub-phase table (0.3–4.3 ms), which Finding 1's correction shows overstates Swift-heavy
   phases. In Release both are well under a millisecond against a 109 ms total, and removing the
   round-trip means adding a second parameter and a fallback path to `make` — apparatus bought
   with a stale measurement. Recorded rather than done, per `docs/plans/README.md`: a plan that
   does not survive contact with the code is a finding.

### Finding 7 — COR-89's premise is falsified: the rebuild is a minority of the command

Stage 0 for COR-89, measured in Release on 2026-08-22 after COR-88. Same corpora, mean of five
iterations per phase, calling the production entry points directly.

| corpus | index | cmark parse | projection model | snapshot | oracle | **rebuild total** | **whole command** |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| degenerateParagraph | 0.1 | 1.4 | 0.0 | 0.0 | 0.00 | **1.5** | 6.3 |
| codeHeavy | 0.1 | 1.1 | 2.3 | 1.3 | 0.05 | **4.8** | 16.3 |
| imageHeavy | 0.1 | 3.5 | 2.6 | 4.1 | 0.29 | **10.3** | 36.8 |
| structuredProse | 0.1 | 4.4 | 3.3 | 3.5 | 0.30 | **11.3** | 40.2 |
| heavyLists | 0.1 | 8.2 | 8.3 | 9.9 | 1.14 | **26.5** | 94.6 |
| tableDense | 0.1 | 13.2 | 8.2 | 5.4 | 0.85 | **26.9** | 96.7 |

**The whole authoritative rebuild is 25–28 % of the command.** COR-89 proposed bounded reparse
with structural sharing to reduce it. Even reducing it to *zero* leaves ~70 ms on `tableDense`
against a 16 ms budget, so the increment as planned cannot close REQ-143. Its premise came from
the Debug phase table, which Finding 1's correction already showed misattributes cost.

Also note the oracle after COR-88: **0.00–1.14 ms**, from 20.5–95.1 ms in Debug before it. The
reformulation is worth far more than the Release end-to-end numbers suggested, because the cost it
removed was concentrated in the configuration where it was measured.

### Finding 8 — where the rest of the command goes

Two measurements narrow it.

A full `AttributedPresentationBuilder.build` over each corpus, Release:

| corpus | rendered chars | blocks | full attributed build |
| --- | ---: | ---: | ---: |
| degenerateParagraph | 100,000 | 1 | 0.6 ms |
| codeHeavy | 70,856 | 2,084 | 38.8 ms |
| imageHeavy | 33,345 | 7,695 | 75.7 ms |
| structuredProse | 60,872 | 2,174 | 105.3 ms |
| heavyLists | 79,636 | 18,520 | 208.5 ms |
| tableDense | 29,280 | 24,400 | 300.4 ms |

The cost is driven by **block count, not character count** — `degenerateParagraph` is the longest
document and the cheapest by two orders of magnitude, at 0.6 ms for one block, while `tableDense`
is the shortest and the most expensive at 300 ms for 24,400 blocks. Roughly 12 µs per block.

A command costs far *less* than a full build (96.7 ms against 300.4 ms on `tableDense`), which is
COR-23's bounded patch route working as designed. Draining every `PerformanceSampler` metric after
one command shows only `semanticCommand` firing — `authoritativeApplication` and
`layoutApplication` are not sampled on this path, so the remaining ~70 ms is unattributed by the
app's own instrumentation.

**Conclusion.** The dominant cost is presentation *application* — deriving the patch between two
whole snapshots and applying it — not the rebuild. COR-89 must be re-planned against that, and
the next measurement has to separate patch derivation from `NSTextStorage` application from
scoped attributed styling. Two of the app's own metrics not firing on its most expensive
interactive path is itself a finding: it is why this had to be measured by hand.

### Finding 5 — Release testability was disabled, so the number that matters was unobtainable

`ENABLE_TESTABILITY = YES` occurs once in `project.pbxproj`, in the **app target's Debug
configuration**. Every test uses `@testable import Markdown_Editor`, so
`xcodebuild test -configuration Release` into clean derived data fails:

```text
error: Unable to resolve Swift module dependency to a compatible module: 'Markdown_Editor'
```

Two live claims depended on that working: ROADMAP COR-18 (*"Debug and Release tests compile and
execute under complete concurrency checking"*) and REQ-090, which cites a focused Release run with
six concrete p95 figures.

**Repaired by COR-86:** `ENABLE_TESTABILITY = YES` now sits in the project-level Release
configuration alongside the Debug one. It is deliberately set on the *shipping* configuration
rather than on a separate benchmark configuration, so that the measured binary and the shipped
binary are the same binary. The cost is a small, uniform inhibition of optimizations that rely on
internal symbols not escaping; the benefit is that no measurement here describes a build nobody
ships.

## Limits

**The phase tables are Debug `-Onone` and must not be quoted as shipping latency.** Finding 4a
supersedes them for absolute numbers; the phase tables remain the evidence for *where* the time
goes, which is what the repairs are aimed at. Note that the measured Release/Debug ratio was
1.2–1.7×, so the phase proportions are more transferable than first assumed.

The corpus is the app's own approved corpus at 100,000 UTF-16 units. Per `CLAUDE.md` §3, that
describes documents of that size and shape and nothing else. `degenerateParagraph` in particular
is 100,000 characters of one repeated word and parses as a single paragraph; it is included here
because it *isolates* the length-driven component of the oracle, which is precisely what makes it
informative rather than misleading in this instance.

Finding 4a *is* driven through the full production route, so it includes selection mapping,
transaction reduction, commit, and presentation install. It still excludes TextKit layout and
draw, which `layoutApplication` budgets separately; real user-visible latency for a command is
therefore **at least** 4a's numbers, not at most.

## Recommendations

Kept separate from the findings above, and not authorized by this document.

1. ~~Restore `ENABLE_TESTABILITY` for Release~~ — done, COR-86. Re-take REQ-090's own evidence.
2. ~~Give the main-actor block a budgeted `PerformanceSampler.Metric`~~ — done, COR-86.
   REQ-143 is `Correction` on the figures in Finding 4a.
3. Reformulate the oracle as a tiling check and delete the round-trip and double construction
   (COR-88).
4. Only then decide, from a Release measurement, whether bounded rebuild is needed (COR-89).
