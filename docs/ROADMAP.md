# ROADMAP

Current delivery state and future sequence. Implemented designs live in code, tests,
[VISION.md](VISION.md), [ENGINEERING.md](ENGINEERING.md), and
[REQUIREMENTS.md](REQUIREMENTS.md)—not in completed plans.

**Status:** ✅ Delivered · 🔵 Active · ⚪ Planned · 🅿️ Parked

## Delivered foundation

The application currently includes:

- ordinary UTF-8 Markdown documents through `NSDocument`;
- New, Open, Save, Save As, autosave, Versions, tabs, Recents, undo/redo, spelling, and Find;
- live-styled literal Source mode;
- formal GFM 0.29 parsing through pinned direct cmark-gfm;
- persistent Source and WYSIWYG TextKit 1 editors with a visible mode toggle;
- delimiter-free editable WYSIWYG presentation and semantic formatting commands;
- task, link, table-cell, image-display, and image-placement interactions;
- exact-copy PNG/JPEG/GIF/HEIC/HEIF placement into a shared sibling `assets/` directory;
- Swift 6 complete concurrency and privacy-safe editor instrumentation;
- session-owned typed mode state, revisioned presentation snapshots, synchronous accepted-edit
  transitions, serialized `NSDocument` I/O, and immutable image-placement intent;
- publication-free editor-host view reconciliation, and local per-run JSON Lines diagnostics
  whose payloads cannot represent document content;
- a hermetic diagnostics-directory override and process-level smoke verification
  (`Scripts/smoke-test.sh`) that a non-UI, structured-log-only exception to §4 permits;
  a complete `EditorTraceEvent` vocabulary with `Scripts/check-instrumentation-coverage.sh`
  guarding against a future unrecorded event; document load and revert outcome instrumentation,
  and save-outcome instrumentation covering every save that determines a destination plus this
  app's own untitled-save bridge — a plain Cmd+S/Save-As panel cancellation is a known,
  documented gap (see `ENGINEERING.md` §9);
  process-level screenshot verification (`Scripts/smoke-screenshot.sh`) capturing one
  window-only screenshot of a rich fixture as mandatory visual-review evidence at the close of
  every app-code increment; image-placement phase/claim/byte/failure instrumentation and one compiler-enforced
  route for every user-visible alert (`ImagePlacementController.presentAlert`), so a presented
  failure or warning can never be absent from the run log.

The exact delivered/correction status of each behavior is recorded in
[REQUIREMENTS.md](REQUIREMENTS.md).

## Active: editor foundation rewrite

The July whole-repository review found that the source/projection ownership model remains sound,
but typography, TextKit application, Release proof, diagnostic lifetime, background scheduling,
resource bounds, and native command presentation do not satisfy the approved architecture.
Affected requirements are marked `Correction`; new approved behavior is `Planned`.

Delivery order:

1. 🔵 **COR-18 — Restore the proof floor.** (Delivers: REQ-088, REQ-104) ([plan](plans/COR-18-proof-floor-reverification.md)) Debug and Release tests compile and execute, the
   shared smoke verifier and typography-rich fixture are landed, and performance evidence
   rejects zero samples.
2. 🔵 **COR-19 — Diagnostic lifetime and shutdown.** (Delivers: REQ-095, REQ-096) ([plan](plans/COR-19-diagnostic-lifetime-reverification.md)) `EditorSession` now detaches its sampler and
   subscriptions, diagnostics serialize directly through an off-main sink, and terminal durability
   no longer waits for main-actor cleanup.
3. 🔵 **INC-05 — Semantic presentation and typography.** (Delivers: REQ-106) ([plan](plans/INC-05-semantic-presentation-reverification.md)) Semantic projection blocks now drive the
   approved typography, reading column, break semantics, list/task alignment, quote/code/table
   treatments, bounded images, thematic separators, and literal HTML styling.
4. ✅ **COR-20 — Incremental TextKit application and honest latency.** (Delivers: REQ-103, REQ-109) Ordinary accepted WYSIWYG
   edits now use validated range patches through `TextStorageApplier`, and performance sampling
   covers the complete native callback plus split parse, image, and application boundaries.
5. 🔵 **COR-21 — Latest-work scheduling and resource bounds.** (Delivers: REQ-076, REQ-081, REQ-112) ([plan](plans/COR-21-latest-work-reverification.md)) Latest parse demand is bounded to
   the running request plus newest pending request, oversized encoded images are rejected from
   metadata before bulk reads, and asset move checks use cmark-derived references.
6. ✅ **INC-06 — Native command surface.** (Delivers: REQ-058, REQ-108) The document-embedded toolbar is replaced by one
   window-scoped command model, native toolbar, menu parity, shared validation, shortcuts, and a
   link-edit sheet.
7. ✅ **COR-22 — Conformance and deletion sweep.** (Delivers: none) Every displaced route deleted, architecture
   proofs rerun, requirements reconciled from evidence, both smoke gates green, Release
   performance evidence recorded, and REQ-104's screenshot captured and reviewed — a review that
   itself found and fixed a caret-shaped task checkmark and a blockquote laying out one character
   per line.
8. ✅ **COR-23 — One patch route for every accepted WYSIWYG change.** (Delivers: REQ-109) Patch scope is derived from
   the real difference between snapshots rather than a declared full-range replacement, so
   formatting commands, task presses, IME commits, and authoritative reconciliation use the
   bounded route. A newer snapshot with unchanged text refreshes only its changed semantic blocks,
   so ARC-Q16's allowlist stays at three full-replacement routes.
9. ✅ **COR-24 — Reliable screenshot capture after display sleep.** (Delivers: none) The existing window-only
   REQ-104 verifier wakes and keeps the local display awake for its bounded run, retaining its
   exact-PID window selection and never falling back to a full-screen capture.
10. ✅ **COR-25 — WYSIWYG list toggle over an ordinary paragraph.** (Delivers: REQ-058) The shared semantic command
    route accepts an exactly mapped ordinary paragraph selection and applies its smallest proven
    list rewrite, without weakening refusal behavior for mixed or synthetic selections.

The editor foundation rewrite is complete.

## Delivered: conformance and liveness program

The August whole-repository review found the source/projection ownership model, the diagnostic
plumbing, and the single-route constructions sound and honestly documented. It also found one
systematic gap: the requirement set, the architecture drivers, and the test suite were built
almost entirely from **safety** properties, with almost no **liveness** properties. REQ-058 was
satisfied by a build in which four formatting commands reported `enabled` and silently refused,
and nine of twelve semantic commands had never been executed through the WYSIWYG route — the
product's default mode — in any test.

1. 🔵 **COR-26 — Enabled implies performable.** (Delivers: REQ-113) ([plan](plans/COR-26-command-liveness.md)) The post-command caret rule is one shared helper
   on `SemanticPlannerGate` instead of arithmetic inlined at one of eleven call sites, so
   `paragraph`, `heading`, `blockQuote`, and `codeBlock` apply rather than refuse.
   `CommandLivenessMatrixTests` is the closed matrix that fails the build when a new command has
   undeclared behavior in either mode.
2. ✅ **COR-27 — TextKit paragraph geometry.** (Delivers: none) Spacing follows semantic boundaries rather than
   every `\n`, so a hard break no longer lays out identically to a paragraph break and a fenced
   block no longer spaces its own lines apart. Proofs assert laid-out line-fragment geometry, not
   attribute values.
3. ✅ **COR-28 — Rendered appearance conformance.** (Delivers: none) Fenced content carries `.codeBlock` rather
   than the inline `.code` tag, so the two treatments cannot compose; toolbar items carry SF
   Symbols instead of rendering blank; and the visual-review fixture can now discriminate a
   correct render from the failure mode ENGINEERING §7 forbids.
4. 🔵 **COR-29 — Instrumentation coverage and honest gates.** (Delivers: REQ-114, REQ-115) ([plan](plans/COR-29-instrumentation-and-gate-honesty.md)) Typed image-resolution failures
   reach the run log, process verification exercises an accepted insertion and an accepted
   command rather than only open-and-idle (19 records → 47), the idle-settle gate dropped from 20
   to 8/4 against a measured-healthy 2, and layout is measured past the input callback.
5. ✅ **COR-30 — Ownership, correctness, and cleanup sweep.** (Delivers: none) Affinity honoured in both
   conversion directions, URL and location generation observed together, one word-count
   implementation, bounded sampler ring, oracle enforced in the WYSIWYG test seam, and
   repository hygiene.
6. 🔵 **COR-31 — Process and traceability gates.** (Delivers: REQ-117, REQ-118) ([plan](plans/COR-31-process-and-traceability-gates.md)) Forward traceability enforced, a `Done`
   requirement can no longer contradict an active increment, `CLAUDE.md` requires liveness proofs
   and laid-out-geometry proofs, and `Scripts/fast-check.sh` is the short inner loop.

## Active: verification integrity programme

The COR-26..COR-31 closing sequence could not produce Release performance evidence, and
investigating why found more than a slow suite. Five defects and one systemic gap, none of them a
regression from that programme — every one reproduces at `a4e170b` (PR #29) or earlier.

The systemic finding governs the ordering below: **REQ-109 sat `Done` for months while four of
its cited proofs were failing.** COR-31's forward-traceability gate checks that a cited proof
*exists*; nothing checks that it *passes*, and the suite containing those proofs never completes,
so the failures were invisible. PR #29's description reported *"Debug 328 passed / 0 failed"*.

This is the same shape as the defect the previous programme fixed, one level up. REQ-058 was
satisfiable by a build where every command refused; "records a test" is satisfiable by a test that
fails. Both contracts checked that a thing existed rather than that it did its job.

COR-32 delivered the systemic fix's prerequisite: the suite executes. Its root cause was not the
suspected cross-test interaction but a real IME-path defect — see the delivered item below.

Delivery order, and why it is this order:

1. ✅ **COR-32 — The performance suite hangs.** (Delivers: none) Root cause found and fixed: `NSTextView.setMarkedText`
   registers an undo operation, and AppKit raises "must begin a group before registering undo"
   because `MarkdownDocument` sets `groupsByEvent = false` (REQ-011 explicit typing groups) and no
   group is open when marked text arrives. The text view now opens the undo group around the native
   marked-text mutation, so real IME composition works and the suite no longer hangs — it executes
   in ~25 s with the four attribute-refresh failures visible in every run (COR-34's scope).
   `Scripts/check-performance-suite.sh` guards the bounded wall-clock time and nonzero case count,
   and the Release evidence has been re-recorded in full. The plan's working hypothesis — an
   *interaction* among the last five tests — was superseded: the hang was `committedComposition-`
   `UsesBoundedPatch` alone, because it is the only test that drives the real marked-text path.
2. 🔵 **COR-34 — Attribute refresh escapes its semantic block.** (Delivers: REQ-078) ([plan](plans/COR-34-attribute-refresh-scope.md)) `PresentationPatch.collectDifferences`
   now compares snapshot arrays **by projection position** instead of by array index, so an element
   inserted, removed, or changed near the start no longer shifts every later element onto a wrong
   counterpart: `hiddenDelimiterCommandRefreshesAttributesWithoutReplacing`,
   `headingAndLinkCommandsRefreshOnlyTheirSelectedBlock`, and
   `attributeRefreshScopeTracksInsertionsAndRemovalsByPosition` prove the refresh stays inside the
   touched semantic blocks. The plan's "four tests, one cause" attribution was partially wrong:
   `taskToggleRefreshesOnlyItsSemanticBlock` failed on a separate, pre-existing source-index
   defect — cmark reports a loose-list item (one followed by a blank line) as ending at the next
   line's column 0, which `MarkdownSourceIndex.utf8Offset` rejected, so the toggle *refused before
   any refresh* in both modes; `MarkdownSourceIndex` now maps end-column-0 to the previous line's
   content end. `resolvedImageRefreshesItsAttachmentOnlyWhenDisplayIdentityChanges` had an
   over-strict assertion (the image block's terminator newline is legitimately refreshed); its
   assertion now checks boundedness to the image block and exclusion of the trailing paragraph.
   Full unified suite: 373 passed, 0 failed. **Second because COR-32 makes these failures visible
   in every run, and they are real product defects, not stale assertions.**
3. 🔵 **COR-35 — A cited proof must pass, not merely exist.** (Delivers: REQ-117, REQ-118) ([plan](plans/COR-35-proofs-must-pass.md)) `Scripts/check-proof-results.sh`
   reads structured results from the run's own `.xcresult` bundle and correlates them with the
   `Done` rows of `REQUIREMENTS.md`: every cited proof must have executed and passed, whether it
   is named as a test or as a suite (REQ-117). The gate **fails closed** — an absent bundle, a
   bundle yielding zero cases, a changed `xcresulttool` schema, or zero resolved rows is a
   failure, not a pass, because a check that silently matches nothing is the same defect wearing
   a new hat.
   REQ-118 is satisfied structurally rather than by a hand-maintained list: a test is mapped when
   a `Done` row cites it or its suite, or when it carries a `// Verifies: REQ-###` anchor — the
   convention the tests already used. Reading the anchors makes the mapping a property of the
   code, so a newly added test fails the gate until it names what it proves. Only three tests are
   exempt, each an absence gate no requirement can cite (`noUITestTargetInProject`,
   `productionForcesNoTextKitLayout`, `productionTestHooksAreInventoried`). A test that names a
   requirement and then fails is reported against that requirement even when `REQUIREMENTS.md`
   does not cite it back — the hole through which
   `resolvedImageRefreshesItsAttachmentOnlyWhenDisplayIdentityChanges` stayed red.
4. ✅ **COR-36 — A nested block discards its parent's indentation.** (Delivers: REQ-107) Reproduced with laid-out
   geometry, and the cause was **not** the one the plan predicted. The parent's style is not
   missing: `MarkdownProjectionModel` emits a list item's child paragraphs *before* the list item
   itself, so the item's style is applied last and wins across the whole item. The defect is in
   `installPerTextKitParagraph` (COR-27): it treated `firstLineHeadIndent` as uniform across the
   block. That value is the *hanging* indent — it positions the line carrying the list marker and
   is one indent step left of `headIndent` — so every later TextKit paragraph in the item began at
   the marker column. A list item's continuation paragraph therefore drew at x=0 while its own
   content indent was 24, and a quote nested in a list item drew at 17 (its rule and padding
   alone). Only the block's first TextKit paragraph now carries the hanging indent.
   `ParagraphGeometryTests.nestedParagraphKeepsItsListItemContentIndent` measures the item's
   content indent from a wrapped line of the item's own text rather than restating
   `MarkdownTypography.listIndent`, and asserts at narrow, default, and wide widths (ARC-Q15);
   `quoteNestedInAListItemKeepsRuleAndIndent` covers the decorated case. `Scripts/Fixtures/`
   `smoke-rich.md` gained a list item with a continuation paragraph so the REQ-104 visual review
   can see this class at all.
5. 🔵 **COR-33 — CRLF code blocks are editable via atomic line breaks.** (Delivers: REQ-113) ([plan](plans/COR-33-crlf-code-block-projection.md)) Stage 1 made `.codeBlock` honest (`disabled(.uneditableContent)` in CRLF); stage 2 makes it performable: `BlockEditPlanner.toggleCodeFence`/`transformLine` now strip `\r` correctly, and `StructuralSourceSpans.fencedCodeBody` + `ProjectionAtom.concreteAtoms` treat each CRLF `\r\n` inside fenced/indented code as a single `.normalizedCodeBlock` atomic (decoder `\r\n→\n`, encoder `\n→\r\n`). Existing CRLF fenced blocks are no longer `.uneditable`; typing one line preserves the other lines' `\r\n` terminators (`CRLFCodeBlockTests.editingOneLinePreservesOtherTerminators`), LF stays byte-identical (`lfDocumentUnchanged`), and `codeBlockIsEditableInCRLFWYSIWYG` now proves `enabled`+`accepted` for both CRLF and LF with `lineReshapingCommandsApplyInCRLFWYSIWYGDocuments` including `.codeBlock`. Mixed line endings remain honest via the same per-line atomic (uniform CRLF → all `\n` re-expand to `\r\n`; LF → identity). `DISC-02` is closed; plan deleted.

6. ✅ **COR-37 — A nested block composes its container.** (Delivers: REQ-107) `AttributedPresentationBuilder.apply(block:)` now composes `textBlocks` instead of replacing wholesale. A fenced code block that is the only child of a quote at `{0,10}` keeps both the quote rule and the padded code background (`codeInsideQuoteComposesBothContainers`); nested quotes accumulate depth via existing `backgroundColor == nil` count. The length-descending stable sort tie is now harmless because both containers compose regardless of order. `nestedBlockQuotesComposeTheirRules` still proves depth via composed count.

Requirements currently `Correction` and the increment that clears each: — none — all `Correction` rows are now `Done`.

Two findings are recorded but deliberately unplanned, so they are not mistaken for oversights:
the plain Cmd+S/Save-panel cancellation gap already documented in `ENGINEERING.md` §9, which is a
deliberate user choice rather than a failure needing a diagnostic; and the `sourceSnapshot()`
location-generation window raised by the PR #33 review, which that review traced as self-healing
through `objectWillChange` re-scheduling and the existing generation gates, and which no
experiment has shown to produce a persistent wrong result.

### Discovery units, not yet researched

**DISC-02 — May projected code-block content be an atomic atom?** — **Closed by COR-33 stage 2.**

Stage 2 proved the vocabulary change via `AtomicRepresentationKind.normalizedCodeBlock` (proven `\r\n↔\n` decoder/encoder, `ProjectionAtom.concreteAtoms` per-line atomic). Fenced and indented code both generalise (same `\r` stripping); raw HTML blocks remain `literalFallback` (non-executing literal, no CRLF decoder needed — they are `muted monospaced` per ENGINEERING §7). Mixed line endings are preserved per-line: each `\r\n` inside code is one atomic, so editing one line leaves the others' `\r\n` byte-identical (REQ-007). The kind gained a case; the existing `htmlEntity`/`backslashEscape` vocabulary was insufficient.

### Delivered: warm CRLF debt

COR-33 left stage-1 debt while warm; COR-38/39 closed it in the minimal debt-close that keeps `REQ-007`/`REQ-113` honest for mixed line endings.

1. 🔵 **COR-38 — Retire COR-33 stage-1 dry-run and make CRLF encoder per-line.** (Delivers: REQ-113) ([plan](plans/COR-38-crlf-cleanup.md)) Stage-1 `canPerformCodeBlock` dry-run with dummy `ID(0)` re-proved via `SemanticEditEngine.plan` what the stage-2 `.normalizedCodeBlock` atomic now guarantees; retired to the default `availability` branch. `MarkdownLiteralEncoder` now carries per-line `originalSource` overload so mixed `LF`/`CRLF` preserves per-line terminators (`CRLFCodeBlockTests.mixedLineEndingsPreserveUntouchedTerminators`); uniform files remain uniform. Helpers `crlfAwareTrimmingNewline()` centralised (4 sites). `REQ-007`/`REQ-113` reconciled.
2. 🔵 **COR-39 — Helpers and single-owner inclusive→exclusive conversion.** (Delivers: REQ-118) ([plan](plans/COR-39-hardening.md)) `MarkdownSourceIndex.inclusiveLastByteToExclusiveEnd` is single owner for the inclusive→exclusive `+1` (ARC-007); `REQ-118` `EXEMPT` is declared in `REQUIREMENTS.md` (spec is source of truth, script reads it, fallback warns). No `hasSuffix("\r\n")` duplication remains; no hard-coded EXEMPT source of truth. **Correction, recorded 2026-08-09:** this increment also claimed `AttributedPresentationBuilder.isQuoteBlock(_:)` was a *typed* predicate for `textBlocks`. It is not — the implementation is still `block.backgroundColor == nil` behind a function name, which a third container kind would collide with. Naming a predicate is not typing it. COR-55 introduces `QuoteTextBlock`/`CodeTextBlock` and makes the claim true.

### Delivered: block identification, hygiene, and decomposition

1. 🔵 **COR-40 — Scope ARC-009 to content mutation; block identification is total for semantic commands.** (Delivers: REQ-057, REQ-113) ([plan](plans/COR-40-scope-arc009-to-content.md)) `ARC-009` now scoped: content mutation (`insertText`/`deleteBackward`/`replaceTableCell`) refuses atomically; `reshapesWholeLine` rewrites identify enclosing `PresentationBlock` by `caretLocation ∈ projectionRange` (total for caret in `renderedString`; `tableCell` stays exact via classifier). `PresentationSnapshot.enclosingBlock(at:)` / `MarkdownProjectionModel.enclosingBlock(at:)` are the single owners. `SemanticBlockIdentificationTests` proves totality at `0`/end and `tableCellStillRequiresExact`; `CommandLivenessMatrixTests` stays green (rehearsed failing via exact gate). Displaced path `guard case .identityText = classification` for `reshapesWholeLine` deleted in same build. `DISC-01` closed.
2. ✅ **COR-41 — Triage hygiene: remove hidden crash, boolean trap, and untestable geometry.** (Delivers: none) No new REQ, no ARC change — `MarkdownHighlighter` `try!` → checked `preconditionFailure`, `WYSIWYGEditor.applyProjectionIfNeeded(force:)` → `ApplyReason` enum, `installPerTextKitParagraph` → `ParagraphStyleInstaller.styles(for:range:text:)`. Proved by existing `ParagraphGeometryTests` at narrow/default/wide widths plus build. Displaced paths `try!` and `force: Bool` deleted; `ParagraphStyleInstaller` is single owner for per-paragraph style. The sweep was not exhaustive: the August review found a force-unwrapped weak document in `ParseCoordinator` and two force-unwrapped UTF-16 alignments in `MarkdownSourceIndex` still present, both scheduled in COR-55.
3. ✅ **COR-42 — Extract ParseCoordinator from EditorSession.** (Delivers: none) `EditorSession` 746 → ~540 lines; `LatestParseScheduler` + `Task` + `operationGeneration` + 200-line `scheduleParse` moved to new `ParseCoordinator` (scheduler + generation + detached pipeline). `EditorSession` keeps `@Published` presentation/mode and delegates via `parseCoordinator`. Visibilities: `presentation`/`resolvedImages`/`authoritativeTree` internal for single external writer, `snapshotIDs`/`performanceSampler` internal, `installPresentation` internal. Build SUCCEEDED, fast-check 368/0 PASS.
4. ✅ **COR-43 — Split SemanticEditEngine by planning domain.** (Delivers: none) `SemanticEditEngine` 1291 → 591 lines router; `SourcePlanningDomain` (153) owns `applySource`, `WYSIWYGPlanningDomain` (576) owns `applyWYSIWYG`/`applyTableCellTyping`/`tablePresentationEdit` + 8 helpers. Engine retains shared helpers as internal and delegates via domains. Build SUCCEEDED, fast-check 368/0 PASS.

## Active: the evidence floor

On 2026-08-10, twelve commits landed directly on `main` — no branch, no worktree, no pull request,
no review, contrary to §5, which has required all four since this repository was created. Ten of
them contain no implementation at all: COR-46 through COR-55 are one comment line each
(`// COR-48: parse scope stub - bounded block reparse would be here`) plus the deletion of their
approved plan. A reconcile commit then read the plans' absence as evidence of delivery and promoted
all ten ROADMAP rows to ✅. COR-44 and COR-45 did land code, but the parts discharging their
requirements were not real: statically dead trace call sites written to satisfy the coverage script,
five empty `WorkScope` closures in an uncalled `private` method, three cited proofs that are
`#expect(Bool(true))`, a fabricated performance baseline, and a duplicated file that left the **test
target unable to compile** — `Scripts/fast-check.sh` reporting `FAILED (2 steps)`, `tests: 0 passed,
0 failed`, while the application target still built green.

Every gate the repository owns passed. `documentation-authority: PASS`.
`instrumentation-coverage: PASS`. Only `check-proof-results.sh` failed, and only because it fails
closed on a stale bundle — it was never run.

**The systemic finding governs the ordering of this programme and supersedes the ordering rationale
of the one below.** The table in that section records three occasions on which a proof obligation was
discharged by a property of the artifact rather than by the behaviour the requirement is about. There
are now six, and the three new ones share a mechanism the first three only hinted at:

| | Contract | What was checked | What was missed |
| --- | --- | --- | --- |
| COR-26 | REQ-058, commands available in both modes | a command reports `enabled` | that it *performs* |
| COR-35 | a `Done` row cites a proof | the proof *exists* | that it *passes* |
| COR-45 | REQ-090, p95 under 8 ms on the approved corpus | a p95 *is measured* | that the corpus is a *document* |
| COR-58 | every trace case has a production call site | a `record` call *appears in source* | that it can *execute* |
| COR-61 | a cited proof discriminates its invariant | the proof *passes* | that it *can fail* |
| COR-59 | an increment is delivered | its plan file is *absent* | that anything was *built* |

Six instances of one pattern is one unfixed design, not six bugs. **Every gate in this repository
asks a question about text, and text is the cheapest thing to produce.** Each gate has been silently
teaching the shape of its own defeat. The instrumentation-coverage script has now been defeated
twice by two different mechanisms — once in July by a same-named unrelated symbol (PR #20), once in
August by a `nil`-bound receiver — because the first defeat was fixed as an instance and never as a
class, which is exactly the failure §6 exists to prevent.

The correction is a single principle, and it is why this programme is expensive: **every proof
obligation must be discharged by an observed execution, never by a property of the source text.**

Delivery order, and why it is this order:

1. ✅ **COR-56 — Restore the record.** *(Delivers: none; record correction)* Reverted the ten
   stub commits and COR-44/45, restored a compiling test target, and left REQ-123..128 standing as
   `Correction` rather than deleting them, since their IDs are cited by the restored plans and
   `CLAUDE.md` §4 never reuses an ID. The restored plan is deleted with this implementation. First,
   because every later increment reasons about a `main` that currently reports work it did not do.
2. ✅ **COR-57 — Enforcement floor.** *(Delivers: REQ-133, REQ-134)* A tracked
   `pre-push` hook via `core.hooksPath`, a push policy that refuses Swift changes going straight to
   the default branch, and gate receipts binding a green run to the SHA it ran against. Implemented
   with fixture-tested branch/refusal and receipt checks; `Scripts/install-hooks.sh` enables it per
   clone. Second,
   because it is hours of work and it would have refused all twelve commits. **Open decision:**
   server-side branch protection needs GitHub Pro or a public repository — the free private plan
   returns `403` — so the hook is enforcement by default, bypassable with `--no-verify` and
   per-clone. The server-side choice is deliberately unresolved, not overlooked.
3. 🔵 **COR-58 — Coverage by observed emission.** *(Delivers: REQ-099, REQ-135)* ([plan](plans/COR-58-observed-emission-coverage.md)) The substring
   scan is deleted; `Scripts/check-instrumentation-coverage.sh` requires all 46
   `EditorTraceEvent` cases in the union of process-smoke and test-run JSON Lines, with a reviewed
   exemption record. Its fixtures reject missing, empty, unknown, and nil-receiver-only evidence.
   Third, because it is the gate defeated twice and the cheapest of the four to make honest.
4. 🔵 **COR-59 — Delivery status is derived, not written.** (Delivers: REQ-136) ([plan](plans/COR-59-derived-delivery-status.md))
   Plans and ROADMAP rows declare `Delivers:`; a ✅
   must resolve to requirements that are `Done` and observed passing; a plan may only be deleted when
   its delivered set is proven in the same run. Makes the 2026-08-10 promotion unrepresentable rather
   than merely discouraged.
5. ✅ **COR-60 — Measurements carry their provenance.** (Delivers: REQ-137) Baselines are
   machine-written with resolving host, OS, architecture, configuration, corpus digest, sample
   counts and commit SHA; the provenance gate and fixture suite pass.
6. ✅ **COR-61 — Every promise has a recorded way to break it.** (Delivers: none) Every retained
   `Done` requirement has a falsification manifest, and the mutation gate observes the cited proof
   turning red.
7. ✅ **COR-62 — Audit the proof floor.** (Delivers: none) All retained `Done`
   rows re-verified against the new gates, hardest-consequence first. It retained only rows with
   observed proofs and recorded the remaining evidence-floor corrections.

The performance programme resumes after the evidence floor: measurements are provenance-bound, and
retained delivery claims have observed falsifying mutations.

## Active: measure, then make it fast, native, and reachable

**Status, corrected 2026-08-11:** COR-44 and COR-45 are delivered and their plans are removed after
observed build, test, benchmark, provenance, and falsification gates. The remaining rows are active
plans and retain their explicit incomplete status.

The August whole-application review read every increment merged that month against `VISION.md`,
`ENGINEERING.md` and `REQUIREMENTS.md`, and against the behaviour of the built application over
`Scripts/Fixtures/smoke-rich.md`. It found the ownership model, the refusal discipline and the
diagnostic plumbing sound. It also found four things a green 368-test suite with every gate passing
could not see.

**The systemic finding governs the ordering.** Three times now a proof obligation has been discharged
by a property of the artifact rather than by the behaviour the requirement is about:

| | Contract | What was checked | What was missed |
| --- | --- | --- | --- |
| COR-26 | REQ-058, commands available in both modes | a command reports `enabled` | that it *performs* |
| COR-35 | a `Done` row cites a proof | the proof *exists* | that it *passes* |
| now | REQ-090, p95 under 8 ms on the approved corpus | a p95 *is measured* | that the corpus is a *document* |

`nativeInputCallbackP95Under8ms` measures `String(repeating: "word ", count: 20_000)` — 100,000 UTF-16
units with no newline, no heading, no list, no table, producing exactly one projection block and one
run. Meanwhile `parseIndexProjectionP95Under100msAt100k`, on a structured corpus of the same size,
measures the same parse-and-project work at 13.9 ms — and `SemanticEditEngine.plan` performs that work
synchronously inside every insertion, with the main thread blocked on `EditorSemanticWorker.sync`'s
semaphore, under cmark's process-wide mutex. The 8 ms budget passes because the corpus is
structurally degenerate.

Nothing in the application counts work, which is why the other findings were equally invisible:
duration metrics cannot distinguish "this document is large" from "this keystroke parsed it four
times". **Measurement therefore comes first.** Until the instruments exist and the corpora are honest,
no performance change in this programme is falsifiable.

Delivery order, and why it is this order:

1. ✅ **COR-44 — Measurement substrate.** (Delivers: REQ-123, REQ-124, REQ-125, REQ-126) A task-local work ledger, main-actor responsiveness probe, real display-link frame statistics, and kernel memory-footprint/peak sampling are wired to production diagnostics and tested.
2. ✅ **COR-45 — Honest corpora and the in-app benchmark harness.** (Delivers: REQ-127, REQ-128)
   A closed `PerformanceCorpus` enumeration whose shapes
   assert their own structure, and a `--benchmark` mode that drives the shipping binary through typing,
   table typing, commands, mode toggles, scrolling, undo storms and a soak, writing a committed
   baseline. Expected to **fail** REQ-090 on landing; that failure is the reproduction.
3. ⚪ **COR-46 — One document build per keystroke.** (Delivers: none)
   ([plan](plans/COR-46-single-build-per-keystroke.md)) One inserted character currently builds the
   whole document two to four times and validates the same immutable snapshot twice. Pure
   de-duplication, no architecture change — bankable immediately.
4. ⚪ **COR-47 — Image identity, sampled digest, and Retina decode.** (Delivers: none)
   ([plan](plans/COR-47-image-identity-and-decode.md)) The display cache keys on a content digest, so
   the expensive work is a *precondition* of the lookup and the cache prevents nothing: every
   referenced image is re-mapped, re-hashed and re-decoded on every reconciliation while the user
   types. Stat identity gates the read; images decode at the backing scale instead of 512 px.
5. ⚪ **COR-48 — Remove the whole-document parse from the keystroke path.** (Delivers: REQ-090)
   ([plan](plans/COR-48-keystroke-parse-scope.md)) The real fix. Opens with a POC comparing "trust the
   encoder, verify offline" against "bounded block reparse", with a decision table that selects a
   branch mechanically. `ARC-005` does not move; the synchronous work gets small, it does not become
   asynchronous.
6. ⚪ **COR-49 — Source-mode performance parity.** (Delivers: none) ([plan](plans/COR-49-source-mode-parity.md)) Source
   mode restyles the whole document on the main actor 120 ms after every keystroke, with no metric, no
   budget and no test. Two genuine editors; one instrumented to the millisecond, one not at all.
7. ⚪ **COR-50 — Semantic bullets.** (Delivers: none) ([plan](plans/COR-50-semantic-bullets.md)) WYSIWYG renders the
   literal source marker, so one semantic list renders three ways depending on whether the author typed
   `-`, `*` or `+`. `**bold**` hides its delimiters; `- item` does not.
8. ⚪ **COR-51 — Accessibility semantics and an AX audit harness.** (Delivers: REQ-129)
   ([plan](plans/COR-51-accessibility-semantics.md)) Six of nine WYSIWYG constructs convey meaning by
   font, colour and indentation alone. A VoiceOver user cannot navigate by heading. REQ-032 is `Done`
   on a proof covering one construct.
9. ⚪ **COR-52 — Visual and layout verification loop.** (Delivers: none)
   ([plan](plans/COR-52-visual-verification-loop.md)) Dark appearance and Source mode have never been
   visually reviewed. Adds diffable layout goldens as the gate and extends ARC-Q13's single capture to
   a declared passive matrix.
10. ⚪ **COR-53 — macOS citizenship.** (Delivers: REQ-130, REQ-131) ([plan](plans/COR-53-macos-citizenship.md)) Window frame memory
    and cascading, Print, heading and block shortcuts, Return continuing a list, a toolbar that fits
    the app's own default window, an Insert menu, and ⌘K with no selection.
11. ⚪ **COR-54 — Correctness fuzzing and real-world corpora.** (Delivers: REQ-132)
    ([plan](plans/COR-54-fuzzing-and-real-corpora.md)) Every fixture in the repository is hand-written.
    Adds the CommonMark and GFM specifications' own example sets, a coordinate round-trip property, edit
    and undo fuzzing, and a differential check against the pinned parser's own renderer.
12. ⚪ **COR-55 — Correctness and hygiene sweep.** (Delivers: none)
    ([plan](plans/COR-55-correctness-and-hygiene.md)) Two crash paths COR-41 missed, a silent paste
    failure with no diagnostic, a layout metric dominated by caret blinks, a duplicated IME commit, and
    the `MarkdownTypography` compatibility facade `ENGINEERING.md` §15 forbids.

## Post-MVP backlog

These are ideas, not commitments. Each requires research, explicit requirements, and approval.

- Named dialect profiles for footnotes, highlight, superscript, subscript, smart typography,
  definition lists, emoji, and heading attributes
- Mermaid diagrams
- YAML front matter
- Wiki-links, transclusion, and tags
- Language-aware fenced-code coloring
- Image sizing with an explicit compatibility contract
- Metadata inspection or stripping
- Save a Copy with Assets
- Ownership-safe unreferenced-asset cleanup
- Remote-image download
- HTML/PDF export
- Focus mode and typewriter scrolling
- Additional themes and user-selectable typography options beyond the approved default
- Document-outline sidebar
