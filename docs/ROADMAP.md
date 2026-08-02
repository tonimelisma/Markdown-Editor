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

### Open defect, reproduced and planned

**`PerformanceBoundaryTests` hangs before executing a single case.** Reproduced on `main`
@`24341da` and on the COR-26..COR-31 branch: the suite reports 0 cases after 4+ minutes with the
test host idle at 0% CPU in `NSApplicationMain` and no test thread present, while every other
suite runs (350 pass through `Scripts/fast-check.sh`, which skips it). It passed as recently as
PR #29. REQ-090 is `Correction` because its Release evidence cannot currently be regenerated.
[Approved plan](plans/COR-32-performance-suite-hang.md).

**Fenced code content is not an identity mapping in CRLF documents.** `.codeBlock` refuses on an
ordinary identity selection in a CRLF document while every other line-reshaping command succeeds:
cmark normalises line endings to `\n`, so a code block's literal and its source span differ by one
UTF-16 unit per line and the post-command caret cannot be projected exactly. Found while fixing
the PR #32 CRLF review comment. [Approved plan](plans/COR-33-crlf-code-block-projection.md).

### Next discovery unit, not yet researched

**DISC-01 — Should semantic commands share the free-form edit coordinate machinery?**

COR-26 corrected the symptom within the current architecture and deliberately did not touch the
cause. The cause is that "exact or refuse" — correct and load-bearing for arbitrary text edits,
where a wrong mapping corrupts a document — is also applied to semantic command dispatch, where a
refusal is not protection but a product defect. "Make this paragraph a list" does not need an
exact inverse mapping of an arbitrary selection; it needs to identify which block the caret is
in, which always succeeds for any caret inside a block.

Two candidate directions, neither approved:

- scope `ARC-009` to content mutation and introduce a separate, weaker, total rule for block
  identification; and/or
- introduce a **semantic selection anchor** — "offset *k* into the content of block *B*" — that
  survives a block rewrite by construction, so no planner reasons about projection coordinates
  and the eleven-call-site caret problem cannot exist.

This changes `ARC-007`/`ARC-009` and therefore requires the full architecture change gate in
`ENGINEERING.md` §15. COR-26's matrix supplies the reproduced counterexample it needs.

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
