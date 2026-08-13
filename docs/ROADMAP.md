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

1. ✅ **COR-18 — Restore the proof floor.** (Delivers: REQ-088, REQ-104) Debug and Release tests compile and execute under complete concurrency checking, the
   shared smoke verifier and typography-rich fixture pass, and the required passive application-window screenshot was captured and reviewed.
2. ✅ **COR-19 — Diagnostic lifetime and shutdown.** (Delivers: REQ-095, REQ-096) `EditorSession` detaches its sampler and
   subscriptions, diagnostics serialize directly through an off-main sink, and terminal durability
   no longer waits for main-actor cleanup. Re-verified on observed `DiagnosticLogTests`/`DiagnosticLifetimeTests`/`ReconciliationInvariantTests` with falsifying mutations.
3. ✅ **INC-05 — Semantic presentation and typography.** (Delivers: REQ-106) Semantic projection blocks drive the
   approved typography, reading column, break semantics, list/task alignment, quote/code/table
   treatments, bounded images, thematic separators, and literal HTML styling. Re-verified on observed `ParagraphGeometryTests`/`AttributedPresentationTests` with falsifying mutation.
4. ✅ **COR-20 — Incremental TextKit application and honest latency.** (Delivers: REQ-103, REQ-109) Ordinary accepted WYSIWYG
   edits now use validated range patches through `TextStorageApplier`, and performance sampling
   covers the complete native callback plus split parse, image, and application boundaries.
5. ✅ **COR-21 — Latest-work scheduling and resource bounds.** (Delivers: REQ-076, REQ-081, REQ-112) Latest parse demand is bounded to
   the running request plus newest pending request, oversized encoded images are rejected from
   metadata before bulk reads, and asset move checks use cmark-derived references. Re-verified on `LatestParseSchedulerTests`/`EncodedImageResourceTests`/`CanonicalAssetReferenceTests` with falsifying mutations.
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

1. ✅ **COR-26 — Enabled implies performable.** (Delivers: REQ-113) The post-command caret rule is one shared helper
   on `SemanticPlannerGate` instead of arithmetic inlined at one of eleven call sites, so
   `paragraph`, `heading`, `blockQuote`, and `codeBlock` apply rather than refuse.
   `CommandLivenessMatrixTests` is the closed matrix that fails the build when a new command has
   undeclared behavior in either mode. Re-verified with falsifying mutation.
2. ✅ **COR-27 — TextKit paragraph geometry.** (Delivers: none) Spacing follows semantic boundaries rather than
   every `\n`, so a hard break no longer lays out identically to a paragraph break and a fenced
   block no longer spaces its own lines apart. Proofs assert laid-out line-fragment geometry, not
   attribute values.
3. ✅ **COR-28 — Rendered appearance conformance.** (Delivers: none) Fenced content carries `.codeBlock` rather
   than the inline `.code` tag, so the two treatments cannot compose; toolbar items carry SF
   Symbols instead of rendering blank; and the visual-review fixture can now discriminate a
   correct render from the failure mode ENGINEERING §7 forbids.
4. ✅ **COR-29 — Instrumentation coverage and honest gates.** (Delivers: REQ-114, REQ-115) Typed image-resolution failures Re-verified with falsifying mutations.
   reach the run log, process verification exercises an accepted insertion and an accepted
   command rather than only open-and-idle (19 records → 47), the idle-settle gate dropped from 20
   to 8/4 against a measured-healthy 2, and layout is measured past the input callback. Re-verified with falsifying mutations.
5. ✅ **COR-30 — Ownership, correctness, and cleanup sweep.** (Delivers: none) Affinity honoured in both
   conversion directions, URL and location generation observed together, one word-count
   implementation, bounded sampler ring, oracle enforced in the WYSIWYG test seam, and
   repository hygiene.
6. ↩️ **COR-31 — Process and traceability gates (historical implementation).** Forward traceability and the fast inner loop landed; COR-68 now owns the observed proof floor.
   requirement can no longer contradict an active increment, `CLAUDE.md` requires liveness proofs
   and laid-out-geometry proofs, and `Scripts/fast-check.sh` is the short inner loop. Re-verified with falsifying mutations.

## Delivered verification and decomposition history

COR-32 through COR-43 repaired the hanging IME test path, bounded attribute refresh, CRLF code-block
editing, nested semantic geometry, block composition, source-index ownership, parse coordination, and
semantic-planning decomposition. Their implementation remains in current production and tests.

Their old detailed delivery ledger is intentionally not repeated here: Git records the sequence, and
current requirement truth lives in REQUIREMENTS. In particular, the earlier COR-35/COR-39 claims for
the proof claims are now enforced by COR-68 because the 2026-08-12 audit found that current falsification could
turn bookkeeping red without weakening production behavior. Likewise, typed quote/code containers,
semantic list-marker source fidelity, shortcut coverage, frame restoration, tabbing, and printing
from the two unreachable checkpoint commits are present in main after squash integration. Their
unreachable commit identities are not WIP and are not used as delivery evidence.

## Active: architecture correction programme

A whole-codebase review on 2026-08-12 re-read the current implementation, tests, gates, plans, and
recent commit history against VISION, ENGINEERING, and REQUIREMENTS. Existing green gates remain
useful regression evidence, but they did not establish all claims they admitted. Eight requirements
are therefore back in Correction: REQ-032, REQ-123, REQ-125, REQ-128. Their rows contain the reproduced
counterexample; no implementation was removed. COR-68 has closed REQ-099, REQ-117, REQ-118, REQ-135,
and REQ-138 with observed production evidence and falsifying mutations.

The review also found partially implemented or obsolete plans. Those plan files are removed as stale
documentation, not as evidence of delivery. Correct parts already in main—including the
squash-integrated semantic-presentation, shortcut, window, printing, and host-state checkpoint
work—are characterized and retained by the replacement plans. No historical patch is replayed.

### Target shape

The durable product choices remain sound: NSDocument owns canonical source/location/revision/undo;
Source and WYSIWYG are persistent native editors; coordinate spaces and revisions are typed; a
presentation is one complete immutable snapshot; full cmark parsing is asynchronous authority; and
image placement is one contained, non-destructive transaction.

The programme makes those choices easier to reason about:

- one pure editor transaction kernel maps typed input plus immutable state to one accepted transaction
  or typed refusal;
- ordinary typing uses a bounded local transition, while full parse/index/projection reconciles
  asynchronously by identity;
- Source highlighting is stateful and incremental by line;
- image display has one metadata-gated, scale-aware service; full SHA-256 belongs only to exact-copy
  asset naming;
- one explicit intent identity survives actor, task, and GCD boundaries;
- route execution, controlled clocks, independent oracles, and production mutations establish proof;
- AppKit adapters become thin construction, input, application, interaction, and layout components.

### Dependency and independence rule

Take plans in the order below. A blocker is an explicit architectural input, not hidden scope. After
its blockers land, each plan is one independently reviewable, revertible increment with distinct
owners, requirement set, route proofs, failure behavior, and deletion gate. An implementation must
not bundle the next plan to make its own proof pass. If observed code contradicts a plan, stop and
return to discovery; do not improvise an architecture change.

1. ✅ **COR-68 — Proof architecture v2.** (Delivers: REQ-099, REQ-117, REQ-118, REQ-135, REQ-138)
   Separates encoding from production reachability, captures observed production records through a
   gate-owned FIFO, binds each route to its owner-specific typed production call, validates
   falsification against production behavior, and gives refactor-only plans derived completion
   evidence. Full gate observed passing: 437 tests, 50 emitted routes, 40 Done rows, 29/29 changed-
   scope falsifications.
2. ⚪ **COR-69 — Intent measurement and honest benchmark.** (Delivers: REQ-123, REQ-125, REQ-128)
   ([plan](plans/COR-69-intent-measurement-and-benchmark.md))
   Carries explicit intent identity across concurrency boundaries, observes main-actor stalls with
   controlled clocks, and makes the shipping benchmark produce its provenance-bound baseline.
3. ⚪ **COR-70 — Editor transaction kernel.** (Delivers: none)
   ([plan](plans/COR-70-editor-transaction-kernel.md)) Extracts one pure input-to-transaction/refusal
   seam and thins AppKit adapters without changing product behavior.
4. ⚪ **COR-71 — Bounded WYSIWYG input.** (Delivers: REQ-090, REQ-091, REQ-092)
   ([plan](plans/COR-71-bounded-wysiwyg-input.md)) Removes whole-document parse/compile work from
   ordinary input while retaining synchronous source/presentation correctness.
5. ⚪ **COR-72 — Incremental Source pipeline.** (Delivers: REQ-040, REQ-041, REQ-043, REQ-045)
   ([plan](plans/COR-72-incremental-source-pipeline.md)) Relexes invalidated lines until lexical state
   stabilizes and applies only matching bounded attribute patches.
6. ⚪ **COR-73 — Image identity and decode service.** (Delivers: REQ-085)
   ([plan](plans/COR-73-image-display-service.md)) Makes metadata identity the cache gate, decode a
   miss-only operation, and backing scale part of immutable request identity.
7. ⚪ **COR-74 — Document files and lifecycle proof.** (Delivers: REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-013, REQ-014, REQ-015, REQ-017, REQ-019, REQ-020, REQ-021)
   ([plan](plans/COR-74-document-files-and-lifecycle.md)) Re-verifies the complete NSDocument file and
   lifecycle boundary through direct construction and precise framework proofs.
8. ⚪ **COR-75 — Native Source editor and privacy contracts.** (Delivers: REQ-010, REQ-011, REQ-012, REQ-022, REQ-030, REQ-031, REQ-044, REQ-046)
   ([plan](plans/COR-75-native-source-editor-and-privacy.md)) Proves native editing liveness and the
   offline/account-free/telemetry-free boundary without custom platform substitutes.
9. ⚪ **COR-76 — Formal-GFM and Source contract.** (Delivers: REQ-047, REQ-048, REQ-049, REQ-050, REQ-053, REQ-054, REQ-055, REQ-056, REQ-059)
   ([plan](plans/COR-76-gfm-source-contract.md)) Gives the pinned dialect one traceable fixture and
   range contract across parser, highlighter, projection, and encoder.
10. ⚪ **COR-77 — WYSIWYG ownership, IME, selection, and undo.** (Delivers: REQ-052, REQ-079, REQ-080, REQ-082, REQ-083, REQ-084, REQ-086, REQ-087, REQ-089, REQ-093, REQ-094)
    ([plan](plans/COR-77-wysiwyg-ownership-ime-and-selection.md)) Closes native callback ownership,
    composition, selection, history, mode, and reconciliation through the transaction kernel.
11. ⚪ **COR-78 — Image placement transaction.** (Delivers: REQ-060, REQ-061, REQ-062, REQ-063, REQ-064, REQ-065, REQ-066, REQ-067, REQ-068, REQ-069, REQ-070, REQ-071, REQ-072, REQ-073, REQ-074, REQ-075, REQ-077)
    ([plan](plans/COR-78-image-placement-transaction.md)) Proves all entry routes share one ordered,
    exact-copy, contained, rollback-safe transaction.
12. ⚪ **COR-79 — Diagnostics and process lifecycle.** (Delivers: REQ-097, REQ-098, REQ-101, REQ-102)
    ([plan](plans/COR-79-diagnostics-and-process-lifecycle.md)) Completes alert/placement diagnostics
    and process smoke using production-route evidence only.
13. ⚪ **COR-80 — Property testing and real corpora.** (Delivers: REQ-132)
    ([plan](plans/COR-80-property-testing-and-real-corpora.md)) Adds deterministic generators,
    shrinkers, independent oracles, and traceable CommonMark/GFM examples after core seams stabilize.
14. ⚪ **COR-81 — Accessibility, contrast, and display preferences.** (Delivers: REQ-032, REQ-129, REQ-139, REQ-141)
    ([plan](plans/COR-81-accessibility-contrast-and-preferences.md)) Gives every semantic and command
    route direct AppKit accessibility proof and closes color/preference policy. REQ-140 remains
    Deferred until a new platform API or separately approved product requirement exists.
15. ⚪ **COR-82 — macOS citizenship.** (Delivers: REQ-130, REQ-131)
    ([plan](plans/COR-82-macos-citizenship.md)) Characterizes already integrated window/shortcut work,
    then completes printing, command organization, list continuation, caret links, and window scope.
16. ⚪ **COR-83 — Release lifecycle and visual conformance.** (Delivers: REQ-142)
    ([plan](plans/COR-83-release-lifecycle-and-visual-conformance.md)) Uses an explicit Stage 0 tool
    decision for leak evidence, closes deterministic owner lifetimes, and verifies real layout over
    the declared semantic/appearance/width/scale/preference matrix.

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
