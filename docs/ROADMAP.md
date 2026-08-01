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

## Active: conformance and liveness program

The August whole-repository review found the source/projection ownership model, the diagnostic
plumbing, and the single-route constructions (`TextStorageApplier`, `ImagePlacementController`)
sound and honestly documented — every identifier cited in REQUIREMENTS resolves to real code, and
both gate scripts genuinely discriminate.

It also found one systematic gap. The requirement set, the architecture drivers, and the test
suite are built almost entirely from **safety** properties — nothing bad happens — with almost no
**liveness** properties. REQ-058 is satisfied by a build in which every formatting command
silently refuses, and four of them did. Nine of twelve semantic commands had never been executed
through the WYSIWYG route — the product's default mode — in any test.

Measured on `88b7bd3` through the real command controller, WYSIWYG selection `{0,16}` over
`"First paragraph.\n\nSecond paragraph.\n"`: `paragraph`, `heading`, `blockQuote`, and `codeBlock`
report `availability == .enabled` and then refuse without mutating source. Each maps exactly to a
`SemanticPlannerGate.commitIfValid` call site that does not pass an explicit `selectionAfter` —
the same root cause COR-25 fixed for one of eleven call sites.

Delivery order:

1. 🔵 **COR-26 — Enabled implies performable.** Hoist the post-command caret rule into the shared
   planner gate so every enabled command performs, and add a command × mode conformance matrix
   that fails the build when a new command has undeclared behavior in either mode.
   [Approved plan](plans/COR-26-command-liveness.md).
2. ⚪ **COR-27 — TextKit paragraph geometry.** A rendered newline that is not a semantic block
   boundary must not collect paragraph spacing, so a hard break stops looking identical to a
   paragraph break and a multi-line fenced block stops spacing its own lines apart. Adds
   laid-out-geometry proofs, not attribute-value proofs.
   [Approved plan](plans/COR-27-textkit-paragraph-geometry.md).
3. ⚪ **COR-28 — Rendered appearance conformance.** Fenced code stops carrying the inline-code
   run background on top of its container, toolbar command items stop rendering as blank buttons,
   and the visual-review fixture gains an image a reviewer can tell apart from the failure mode
   ENGINEERING forbids. [Approved plan](plans/COR-28-rendered-appearance-conformance.md).
4. ⚪ **COR-29 — Instrumentation coverage and honest gates.** Typed local-image resolution
   failures reach the run log, process-level verification exercises an accepted edit and a
   semantic command rather than only open-and-idle, the idle-settle gate drops from 20 to 4
   against a measured-healthy 2, and latency is measured past the input callback into layout.
   [Approved plan](plans/COR-29-instrumentation-and-gate-honesty.md).
5. ⚪ **COR-30 — Ownership, correctness, and cleanup sweep.** Affinity honoured in both conversion
   directions, `fileURL` and `locationGeneration` observed atomically, one word-count
   implementation instead of two, bounded sampler buffer, oracle enforced in the WYSIWYG test
   seam, one test framework, and repository hygiene.
   [Approved plan](plans/COR-30-ownership-and-cleanup.md).
6. ⚪ **COR-31 — Process and traceability gates.** Forward traceability enforced, a `Done`
   requirement can no longer contradict an open defect, `CLAUDE.md` requires a liveness proof for
   every user-invocable action and laid-out-geometry proof for every appearance requirement, and
   a short inner loop exists alongside the full one.
   [Approved plan](plans/COR-31-process-and-traceability-gates.md).

### Next discovery unit, not yet researched

**DISC-01 — Should semantic commands share the free-form edit coordinate machinery?**

COR-26 corrects the symptom within the current architecture and deliberately does not touch the
cause. The cause is that "exact or refuse" — correct and load-bearing for arbitrary text edits,
where a wrong mapping corrupts a document — is also applied to semantic command dispatch, where a
refusal is not protection but a product defect: the user pressed a button and nothing happened.
"Make this paragraph a list" does not need an exact inverse mapping of an arbitrary selection; it
needs to identify which block the caret is in, which always succeeds for any caret inside a block.

Two candidate directions, neither approved:

- scope `ARC-009` to content mutation and introduce a separate, weaker, total rule for block
  identification; and/or
- introduce a **semantic selection anchor** — "offset *k* into the content of block *B*" — that
  survives a block rewrite by construction, so no planner reasons about projection coordinates
  and the eleven-call-site caret problem cannot exist.

This changes `ARC-007`/`ARC-009` and therefore requires the full architecture change gate in
`ENGINEERING.md` §15: a reproduced counterexample (COR-26's matrix supplies it), fresh research
and real API probes, credible options compared against the architecture drivers, explicit
approval, an atomic ENGINEERING and requirements update, a discriminating executable proof, and
deletion of the displaced path in the same build. It is recorded here so the cause is not lost
now that the symptom is scheduled.

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
