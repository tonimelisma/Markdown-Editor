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

1. ✅ **COR-18 — Restore the proof floor.** Debug and Release tests compile and execute, the
   shared smoke verifier and typography-rich fixture are landed, and performance evidence
   rejects zero samples.
2. ✅ **COR-19 — Diagnostic lifetime and shutdown.** `EditorSession` now detaches its sampler and
   subscriptions, diagnostics serialize directly through an off-main sink, and terminal durability
   no longer waits for main-actor cleanup.
3. ✅ **INC-05 — Semantic presentation and typography.** Semantic projection blocks now drive the
   approved typography, reading column, break semantics, list/task alignment, quote/code/table
   treatments, bounded images, thematic separators, and literal HTML styling.
4. ✅ **COR-20 — Incremental TextKit application and honest latency.** Ordinary accepted WYSIWYG
   edits now use validated range patches through `TextStorageApplier`, and performance sampling
   covers the complete native callback plus split parse, image, and application boundaries.
5. ✅ **COR-21 — Latest-work scheduling and resource bounds.** Latest parse demand is bounded to
   the running request plus newest pending request, oversized encoded images are rejected from
   metadata before bulk reads, and asset move checks use cmark-derived references.
6. ✅ **INC-06 — Native command surface.** The document-embedded toolbar is replaced by one
   window-scoped command model, native toolbar, menu parity, shared validation, shortcuts, and a
   link-edit sheet.
7. ✅ **COR-22 — Conformance and deletion sweep.** Every displaced route deleted, architecture
   proofs rerun, requirements reconciled from evidence, both smoke gates green, Release
   performance evidence recorded, and REQ-104's screenshot captured and reviewed — a review that
   itself found and fixed a caret-shaped task checkmark and a blockquote laying out one character
   per line.
8. ✅ **COR-23 — One patch route for every accepted WYSIWYG change.** Patch scope is derived from
   the real difference between snapshots rather than a declared full-range replacement, so
   formatting commands, task presses, IME commits, and authoritative reconciliation use the
   bounded route. A newer snapshot with unchanged text refreshes only its changed semantic blocks,
   so ARC-Q16's allowlist stays at three full-replacement routes.
9. ✅ **COR-24 — Reliable screenshot capture after display sleep.** The existing window-only
   REQ-104 verifier wakes and keeps the local display awake for its bounded run, retaining its
   exact-PID window selection and never falling back to a full-screen capture.
10. ✅ **COR-25 — WYSIWYG list toggle over an ordinary paragraph.** The shared semantic command
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

1. ✅ **COR-26 — Enabled implies performable.** The post-command caret rule is one shared helper
   on `SemanticPlannerGate` instead of arithmetic inlined at one of eleven call sites, so
   `paragraph`, `heading`, `blockQuote`, and `codeBlock` apply rather than refuse.
   `CommandLivenessMatrixTests` is the closed matrix that fails the build when a new command has
   undeclared behavior in either mode.
2. ✅ **COR-27 — TextKit paragraph geometry.** Spacing follows semantic boundaries rather than
   every `\n`, so a hard break no longer lays out identically to a paragraph break and a fenced
   block no longer spaces its own lines apart. Proofs assert laid-out line-fragment geometry, not
   attribute values.
3. ✅ **COR-28 — Rendered appearance conformance.** Fenced content carries `.codeBlock` rather
   than the inline `.code` tag, so the two treatments cannot compose; toolbar items carry SF
   Symbols instead of rendering blank; and the visual-review fixture can now discriminate a
   correct render from the failure mode ENGINEERING §7 forbids.
4. ✅ **COR-29 — Instrumentation coverage and honest gates.** Typed image-resolution failures
   reach the run log, process verification exercises an accepted insertion and an accepted
   command rather than only open-and-idle (19 records → 47), the idle-settle gate dropped from 20
   to 8/4 against a measured-healthy 2, and layout is measured past the input callback.
5. ✅ **COR-30 — Ownership, correctness, and cleanup sweep.** Affinity honoured in both
   conversion directions, URL and location generation observed together, one word-count
   implementation, bounded sampler ring, oracle enforced in the WYSIWYG test seam, and
   repository hygiene.
6. ✅ **COR-31 — Process and traceability gates.** Forward traceability enforced, a `Done`
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

1. ✅ **COR-32 — The performance suite hangs.** Root cause found and fixed: `NSTextView.setMarkedText`
   registers an undo operation, and AppKit raises "must begin a group before registering undo"
   because `MarkdownDocument` sets `groupsByEvent = false` (REQ-011 explicit typing groups) and no
   group is open when marked text arrives. The text view now opens the undo group around the native
   marked-text mutation, so real IME composition works and the suite no longer hangs — it executes
   in ~25 s with the four attribute-refresh failures visible in every run (COR-34's scope).
   `Scripts/check-performance-suite.sh` guards the bounded wall-clock time and nonzero case count,
   and the Release evidence has been re-recorded in full. The plan's working hypothesis — an
   *interaction* among the last five tests — was superseded: the hang was `committedComposition-`
   `UsesBoundedPatch` alone, because it is the only test that drives the real marked-text path.
2. ✅ **COR-34 — Attribute refresh escapes its semantic block.** `PresentationPatch.collectDifferences`
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
3. ✅ **COR-35 — A cited proof must pass, not merely exist.** `Scripts/check-proof-results.sh`
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
4. ✅ **COR-36 — A nested block discards its parent's indentation.** Reproduced with laid-out
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
5. ✅ **COR-33 — CRLF code blocks are editable via atomic line breaks.** Stage 1 made `.codeBlock` honest (`disabled(.uneditableContent)` in CRLF); stage 2 makes it performable: `BlockEditPlanner.toggleCodeFence`/`transformLine` now strip `\r` correctly, and `StructuralSourceSpans.fencedCodeBody` + `ProjectionAtom.concreteAtoms` treat each CRLF `\r\n` inside fenced/indented code as a single `.normalizedCodeBlock` atomic (decoder `\r\n→\n`, encoder `\n→\r\n`). Existing CRLF fenced blocks are no longer `.uneditable`; typing one line preserves the other lines' `\r\n` terminators (`CRLFCodeBlockTests.editingOneLinePreservesOtherTerminators`), LF stays byte-identical (`lfDocumentUnchanged`), and `codeBlockIsEditableInCRLFWYSIWYG` now proves `enabled`+`accepted` for both CRLF and LF with `lineReshapingCommandsApplyInCRLFWYSIWYGDocuments` including `.codeBlock`. Mixed line endings remain honest via the same per-line atomic (uniform CRLF → all `\n` re-expand to `\r\n`; LF → identity). `DISC-02` is closed; plan deleted.

6. ✅ **COR-37 — A nested block composes its container.** `AttributedPresentationBuilder.apply(block:)` now composes `textBlocks` instead of replacing wholesale. A fenced code block that is the only child of a quote at `{0,10}` keeps both the quote rule and the padded code background (`codeInsideQuoteComposesBothContainers`); nested quotes accumulate depth via existing `backgroundColor == nil` count. The length-descending stable sort tie is now harmless because both containers compose regardless of order. `nestedBlockQuotesComposeTheirRules` still proves depth via composed count.

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

1. ✅ **COR-38 — Retire COR-33 stage-1 dry-run and make CRLF encoder per-line.** Stage-1 `canPerformCodeBlock` dry-run with dummy `ID(0)` re-proved via `SemanticEditEngine.plan` what the stage-2 `.normalizedCodeBlock` atomic now guarantees; retired to the default `availability` branch. `MarkdownLiteralEncoder` now carries per-line `originalSource` overload so mixed `LF`/`CRLF` preserves per-line terminators (`CRLFCodeBlockTests.mixedLineEndingsPreserveUntouchedTerminators`); uniform files remain uniform. Helpers `crlfAwareTrimmingNewline()` centralised (4 sites). `REQ-007`/`REQ-113` reconciled.
2. ✅ **COR-39 — Helpers and typed block-container predicate.** `MarkdownSourceIndex.inclusiveLastByteToExclusiveEnd` is single owner for inclusive→exclusive `+1` (ARC-007); `AttributedPresentationBuilder.isQuoteBlock(_:)` is typed predicate for `textBlocks` (was `backgroundColor == nil`); `REQ-118` `EXEMPT` now declared in `REQUIREMENTS.md` (spec is source of truth, script reads it, fallback warns). No `hasSuffix("\r\n")` duplication remains; no hard-coded EXEMPT source of truth.

### Active: scope ARC-009 to content — semantic block identification is total

1. 🔵 **COR-40 — Scope ARC-009 to content mutation; block identification is total for semantic commands** — see [`docs/plans/COR-40-scope-arc009-to-content.md`](plans/COR-40-scope-arc009-to-content.md). `ARC-009` exact-or-refuse stays for `insertText`/`deleteBackward`/`replaceTableCell`; `reshapesWholeLine` block rewrites identify the enclosing `PresentationBlock` by `caretLocation ∈ projectionRange` (total for caret in `renderedString`; `tableCell` stays exact). Bounded POCs `8/8 PASS`, scored 4.5/5 vs anchor 3.9/5; the anchor is deferred until a block kind needs it. `§15` gate (counterexample `CommandLivenessMatrixTests` COR-26, research, scored options, explicit approval 2026-08-06) satisfied for this scope change.

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
