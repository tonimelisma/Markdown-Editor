# COR-48 — Remove the whole-document parse from the keystroke path

- **Status:** Approved; not implemented
- **Requirements:** REQ-090 (returns to `Done`), REQ-091, REQ-092, REQ-109, REQ-113, REQ-123
- **Delivers:** REQ-090
- **ARC invariants:** ARC-005, ARC-007, ARC-Q07 unchanged and load-bearing. ARC-Q06 gains a liveness clause ("off the main actor **and without blocking it**"). Whether the projection scope changes is decided by Phase 0's decision table; if it does, `ENGINEERING.md` §6 is amended atomically with the build, per §15.

## Context

Every non-empty WYSIWYG insertion performs at least one complete-document cmark parse plus source
index plus projection compile, synchronously, with the main thread blocked.

`SemanticEditEngine.plan` (`:180`) calls `literalCandidatePreservesPresentation`, which calls
`AuthoritativePresentationBuilder.build` on the complete post-edit source. That runs inside
`EditorSemanticWorker.sync` (`EditorSemanticWorker.swift:23`), which dispatches to a worker queue and
then blocks the calling thread on a `DispatchSemaphore`. ARC-Q06 ("the parser does not execute on the
main actor") is satisfied to the letter while the main thread is unavailable for the whole duration —
the invariant holds and the responsiveness driver it exists to serve does not.

It compounds three ways:

1. `MarkdownParser.parse` takes a **process-wide `Mutex`** (`MarkdownParser.swift:24`). The background
   reconciliation parse for the previous keystroke may hold it, so the main thread can block on a
   semaphore waiting on a worker blocked on a mutex held by a full background parse, and then perform
   its own. Worst case is roughly two whole-document parses of main-thread stall per character.
2. One keystroke can build the document up to four times. COR-46 reduces that to one; this increment
   addresses the remaining one.
3. Table-cell typing takes the expensive route unconditionally (`SemanticEditEngine.swift:138`).

`deleteBackward` is genuinely cheap — an empty replacement skips the block at `:157` and goes straight
to `finishIdentityTransition`. Deletion is fast and insertion is not, which is a useful diagnostic
signature and a strong hint that the insertion path's cost is incidental rather than essential.

Measured floor on a realistically structured 100,000-unit document: 13.9 ms
(`parseIndexProjectionP95Under100msAt100k`), against an 8 ms budget, before TextKit lays anything out.
At 1 MB it exceeds 100 ms per character and `MainActorWatchdog` begins correctly reporting stalls.

## Phase 0 — POC: both candidates, one run

Throwaway target `/POC/KeystrokeScope/`, deleted before the PR opens.

### Candidate A — trust the encoder, verify offline

`MarkdownLiteralEncoder.encode` already returns "the minimum source spelling that renders as exactly
this visible text in this context". If that contract holds, the runtime reparse re-derives a guarantee
the encoder has already made, and verification belongs in CI rather than in every keystroke.

Enumerate the encoder's full input space:

- `intendedVisibleText` ∈ every character in `` * _ ` ~ # > | [ ] ( ) ! \ - + . ``, the digits, space,
  tab, one ordinary letter, and one astral-plane emoji;
- `precedingSourceCharacter` × `followingSourceCharacter` ∈ {nil, letter, space, newline, each
  Markdown-active character};
- `atLineStart` ∈ {true, false};
- `container` ∈ every `LiteralEncodeContext.LiteralContainer` case.

Apply each cell to carrier documents: one per `PerformanceCorpus` shape plus adversarial carriers —
inside a link label, inside a table cell, on a setext underline line, immediately before a fence,
inside an HTML block, inside a link reference definition. Compare the encoder's own decision against
the current full-reparse verdict. Record the agreement rate overall and per container.

### Candidate B — bounded block reparse

Reparse only the enclosing top-level block's source window rather than the document.

| # | Probe |
| --- | --- |
| B1 | `[ref]: https://x` in block 1 and `[text][ref]` in block 9; parse block 9 alone; compare (document-scoped link reference definitions) |
| B2 | Window ending in a paragraph followed by `> quote`; parse with and without the following line (lazy continuation) |
| B3 | Window starting with `===` (setext underline reaching backwards) |
| B4 | Window containing an unclosed fence or an open HTML block |
| B5 | An item followed by a blank line then another item outside the window (list tightness) |
| B6 | Parse a fragment, add the window's start offset to every `cmark_node` position, and compare against the same node in the full parse |

Measure, on every corpus shape at 100k and 1M: p50 and p95 of (A) the encoder decision alone,
(B) a block-window reparse, and the current full build.

### Decision table — applied mechanically

| Observation | Branch |
| --- | --- |
| A agrees with the reparse in **100 %** of cells | **A-full.** `literalCandidatePreservesPresentation` leaves the runtime entirely and becomes the matrix test. Keystroke cost becomes O(edit). |
| A agrees in ≥ 95 %, disagreements confined to identifiable containers | **A-partial.** `encode` returns `.encoded(spelling, guarantee: .structurallyInert \| .requiresVerification)`. Inert skips the reparse; verification falls to B when B is viable, otherwise to the full build. Record the per-container split. |
| A agrees in < 95 % | **A rejected.** Record why; proceed on B. |
| B1–B6 all yield "provably independent, or detectably dependent from the existing `MarkdownTree` without reparsing" | **B viable.** Implement `SourceReparseWindow`; detectable-dependency cases refuse to the full path. |
| Any B probe yields "dependent and undetectable" | **B rejected.** Record the probe and its output verbatim. |
| **A and B both rejected** | Stop the build unit, delete the branch, open a separate discovery unit. Taking this escape hatch is a success of the process, not a failure of the increment — it must remain reachable. |

**Then, without stopping:** write `docs/research/DISC-04-keystroke-parse-scope.md` (evidence-only
authority, dates, macOS/SDK/cmark versions, method, the full matrix for A, the six probe outputs for
B, the cost table, and the branch taken), delete the POC, rewrite Phases 1+ of this plan from the
chosen branch, commit the rewrite, and continue into implementation.

## Phase 1+ — deliverables fixed regardless of branch

1. **`EditorSemanticWorker.sync` is deleted.** Blocking the main thread on a semaphore while claiming
   the work is off the main actor satisfies ARC-Q06's wording and defeats its purpose. If any caller
   survives the increment, `ENGINEERING.md` §9 must name it explicitly as a blocking boundary and
   ARC-Q06 must be reworded with the exception enumerated — the invariant is corrected, never left
   quietly untrue.
2. **ARC-Q06 gains a liveness clause.** A proof that the main thread is *not blocked*, not merely that
   work runs elsewhere: across a `typeProse` benchmark run, `WorkLedger.mainThreadBlockedNanos` is 0
   and `mainActorLatency` p95 stays within budget.
3. **REQ-090 returns to `Done`**, with every `PerformanceCorpus` shape passing at 100k and a
   non-gating 1M characterisation recorded per shape.
4. **The table-cell route uses the same bounded path.** It is not left as a special case that reparses
   the document; ARC-005 applies to a cell edit exactly as it applies to a paragraph edit.

## Invariants that do not move, whatever Phase 0 finds

- **ARC-005 stands.** An accepted WYSIWYG edit still advances source and presentation synchronously
  and exactly once. Committing source and leaving the old projection editable remains forbidden. The
  fix makes the synchronous work small; it does not make it asynchronous. This is the invariant that
  makes the editor correct, and it is not available as a performance lever.
- **ARC-007 stands.** Every coordinate is exact or a typed refusal.
- **ARC-Q07 stands.** The oracle validates every snapshot that reaches storage.

## Proof

- COR-45's `nativeInputCallbackP95Under8ms`, `tableCellKeystrokeP95Under8ms` and
  `adjacentMarkupKeystrokeP95Under8ms`, all parameterised over `PerformanceCorpus.allCases`, move from
  failing to passing. This is the increment's definition of success.
- `acceptedEditPerformsBoundedWork` — `documentParses == 0` on the branch taken (A-full) or
  `documentParses <= 1` bounded to a block window (B).
- `mainThreadIsNotBlockedDuringAnAcceptedEdit` — occupy the main run loop with a counter during a
  keystroke; assert the counter advanced. **Rehearsed failing** against today's semaphore.
- Under branch A, the offline matrix `encoderGuaranteeAgreesWithAFullReparse` replaces the runtime
  check and is parameterised over the full Phase 0 input space, so a future encoder change that breaks
  the guarantee fails the build.
- Under branch B, `blockWindowProjectionMatchesTheFullDocumentProjection` over every corpus shape and
  every adversarial carrier, plus explicit refusal proofs for each detectable-dependency case.
- Existing `AcceptedEditTransactionTests`, `CommandLivenessMatrixTests`, `CRLFCodeBlockTests`,
  `ProjectionCharacterizationTests` and the oracle suites remain green — correctness is not traded for
  latency.

## Instrumentation and performance evidence

Re-record `docs/research/performance-baseline.md` with the before/after for every scenario and corpus.
Record `mainActorLatency` p95 and frame hitch ms/s during `typeProse` at 100k and 1M — the two numbers
that describe what the user feels, neither of which existed before COR-44.

## Failure / rollback

The highest-risk increment in the programme, so its risk is structural rather than incidental: a
wrongly-scoped projection would produce a *silently wrong document*, which is worse than a slow one.
Controls, in order:

- The oracle (ARC-Q07) validates every snapshot reaching storage and is not bypassed for the fast path.
- `finishIdentityTransition` already refuses when the transition cannot be proven; the branch taken
  narrows what is attempted, never what is verified.
- Phase 0's decision table has an explicit "both rejected" outcome that deletes the branch rather than
  shipping a guess.
- COR-54's spec-corpus and round-trip fuzzing runs against this increment before merge.

If any correctness proof regresses, revert the branch entirely and return to the discovery unit. A
partial landing is not available: half a scoping rule is a scoping rule that is wrong half the time.

## Deletion / conformance gate

- `EditorSemanticWorker.sync` is deleted, or its surviving callers are enumerated in
  `ENGINEERING.md` §9 with ARC-Q06 reworded in the same commit.
- The displaced route — whichever of `literalCandidatePreservesPresentation`'s runtime reparse or the
  unconditional table-cell `planAuthoritativeTransition` the branch removes — is deleted in this
  build, not left behind a flag (`ENGINEERING.md` §15: no compatibility layers, no indefinite
  migrations).
- `docs/plans/COR-48-keystroke-parse-scope.md` is deleted in the implementing change.
- `Scripts/check-documentation-authority.sh`, `Scripts/check-instrumentation-coverage.sh`,
  `Scripts/check-proof-results.sh`, both smoke scripts, and the Release performance proof all pass.
