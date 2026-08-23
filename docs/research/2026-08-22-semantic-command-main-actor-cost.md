# Semantic command main-actor cost

- **Authority:** evidence only. Not a product decision and not a repair plan. The repairs it
  motivates are `docs/plans/COR-86…COR-90`.
- **First researched:** 2026-08-22
- **Last verified:** 2026-08-22
- **Environment:** macOS 27.0 (build 26A5416b), Darwin 27.0.0, arm64. Xcode 27.0 (27A5228h).
  **Debug, `SWIFT_OPTIMIZATION_LEVEL = -Onone`.** See *Limits* — the Release figure that matters
  could not be taken.
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

### Finding 1 — the oracle costs more than the parse it validates

`ProjectionOracle.validate` is the largest single cost in a formatting command, and on every
corpus case it exceeds the cmark parse whose output it checks — 95.1 ms against 27.5 ms on
`heavyLists`, a factor of 3.5.

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

### Finding 5 — Release testability is disabled, so the number that matters is unobtainable

`ENABLE_TESTABILITY = YES` occurs once in `project.pbxproj`, in the **app target's Debug
configuration**. Every test uses `@testable import Markdown_Editor`, so
`xcodebuild test -configuration Release` into clean derived data fails:

```text
error: Unable to resolve Swift module dependency to a compatible module: 'Markdown_Editor'
```

Two live claims depend on that working: ROADMAP COR-18 (*"Debug and Release tests compile and
execute under complete concurrency checking"*) and REQ-090, which cites a focused Release run with
six concrete p95 figures. Those figures cannot be reproduced today without a project change that
was never recorded.

## Limits

**These are Debug `-Onone` numbers and must not be quoted as shipping latency.** cmark is C and
largely unaffected by Swift optimization; the Swift-heavy phases — the oracle's per-character
loop, atom construction, projection model build — should improve substantially in Release. The
ratios between phases are the durable part of this evidence; the absolute values are not.

The corpus is the app's own approved corpus at 100,000 UTF-16 units. Per `CLAUDE.md` §3, that
describes documents of that size and shape and nothing else. `degenerateParagraph` in particular
is 100,000 characters of one repeated word and parses as a single paragraph; it is included here
because it *isolates* the length-driven component of the oracle, which is precisely what makes it
informative rather than misleading in this instance.

No measurement was taken of a command driven through the full production `EditorSession` route,
so the figures exclude selection mapping, transaction reduction, TextKit application, and layout.
The real user-visible latency is therefore **at least** these numbers, not at most.

## Recommendations

Kept separate from the findings above, and not authorized by this document.

1. Restore `ENABLE_TESTABILITY` for Release and re-take REQ-090's evidence (COR-86).
2. Give the main-actor block a budgeted `PerformanceSampler.Metric` so it is bounded rather than
   merely recorded (COR-86).
3. Reformulate the oracle as a tiling check and delete the round-trip and double construction
   (COR-88).
4. Only then decide, from a Release measurement, whether bounded rebuild is needed (COR-89).
