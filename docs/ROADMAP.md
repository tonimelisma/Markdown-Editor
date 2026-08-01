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
7. 🔵 **[COR-22 — Conformance and deletion sweep](plans/cor-22-rewrite-conformance-and-deletion.md).** Delete every displaced route, rerun all
   architecture proofs, reconcile requirements from evidence, and close the rewrite program.
   Conformance, deletion, Debug and Release suites, both smoke gates, and Release performance
   evidence are complete. The program stays Active on two items:
   1. REQ-104's mandatory window-only screenshot cannot be captured because the calling process
      lacks Screen Recording permission, so the required visual review has not happened.
   2. REQ-109 returned to `Correction`: separate-agent review found that semantic formatting
      commands still apply a whole-document attributed replacement, a fourth full-replacement
      route ARC-Q16 does not permit. Closing it changes where a patch is derived, so it needs a
      separately approved discovery unit rather than an edit inside this build.

The exact approved implementation work lives in the corresponding files under `docs/plans/`.

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
