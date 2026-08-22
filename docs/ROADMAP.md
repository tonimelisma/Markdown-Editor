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
  a complete `EditorTraceEvent` vocabulary with `CommandLivenessMatrixTests`
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

1. ✅ **COR-18 — Restore the proof floor.** Debug and Release tests compile and execute under complete concurrency checking, the
   shared smoke verifier and typography-rich fixture pass, and the required passive application-window screenshot was captured and reviewed.
2. ✅ **COR-19 — Diagnostic lifetime and shutdown.** `EditorSession` detaches its sampler and
   subscriptions, diagnostics serialize directly through an off-main sink, and terminal durability
   no longer waits for main-actor cleanup.
3. ✅ **INC-05 — Semantic presentation and typography.** Semantic projection blocks drive the
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
6. ↩️ **COR-31 — Process and traceability gates (historical implementation).** Forward traceability and the fast inner loop landed; COR-68 now owns the observed proof floor.
   requirement can no longer contradict an active increment, `CLAUDE.md` requires liveness proofs
   and laid-out-geometry proofs, and `Scripts/check.sh` is the loop.

## Delivered verification and decomposition history

COR-32 through COR-43 repaired the hanging IME test path, bounded attribute refresh, CRLF code-block
editing, nested semantic geometry, block composition, source-index ownership, parse coordination, and
semantic-planning decomposition. Their implementation remains in current production and tests.

Their old detailed delivery ledger is intentionally not repeated here: Git records the sequence, and
current requirement truth lives in REQUIREMENTS. Likewise, typed quote/code containers,
semantic list-marker source fidelity, shortcut coverage, frame restoration, tabbing, and printing
from the two unreachable checkpoint commits are present in main after squash integration. Their
unreachable commit identities are not WIP and are not used as delivery evidence.

## Active: architecture correction programme

A whole-codebase review on 2026-08-12 re-read the current implementation, tests, gates, plans, and
recent commit history against VISION, ENGINEERING, and REQUIREMENTS. Existing green gates remain
useful regression evidence, but they did not establish all claims they admitted. REQ-032 remains in
Correction with its reproduced counterexample; no implementation was removed. COR-68 closed REQ-099 with observed
production evidence, and COR-69 closed REQ-123, REQ-125, and REQ-128. The process requirements
those increments also introduced (REQ-117/118/133–138) were retired on 2026-08-22 along with the
gates that implemented them; see `docs/DECISIONS.md`.

The review also found partially implemented or obsolete plans. Those plan files were removed as stale
documentation, not as evidence of delivery. Correct parts already in main—including the
squash-integrated semantic-presentation, shortcut, window, printing, and host-state checkpoint
work—are characterized and retained by the replacement plans. COR-69's plan was removed only after its requirements and
proofs were observed passing; the remaining pending plans are the active backlog. No historical patch is replayed.

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

1. ✅ **COR-68 — Proof architecture v2.**
   Separates encoding from production reachability, captures observed production records through a
   gate-owned FIFO, binds each route to its owner-specific typed production call, validates
   evidence. Full gate observed passing: 437 tests, 50 emitted routes, 40 Done rows.
2. ✅ **COR-69 — Intent measurement and honest benchmark.**
   Carries explicit intent identity across concurrency boundaries, observes main-actor stalls with
   controlled clocks, and makes the shipping benchmark produce its provenance-bound baseline. The
   final full gate observed 454 passing tests, 50 production trace routes
   and a 108-case Release baseline; process smoke diagnostics also passed.
3. ✅ **COR-70 — Editor transaction kernel.**
   Extracts one pure input-to-transaction/refusal seam and thins AppKit adapters without changing
   product behavior. Delivered with owner-state validation, atomic refusal behavior, and real
   source/WYSIWYG route proofs; the full gate observed 476 passing tests and zero failures.
4. ✅ **COR-71 — Bounded WYSIWYG input.**
   Removes whole-document parse/compile work from ordinary input while retaining synchronous
   source/presentation correctness. The closed local-transition matrix accepts only proven
   identity/atomic edits and source-boundary synthetic insertions, uses one bounded enclosing-block
   path for table cells, and keeps source-location synthetic/task-marker/ambiguous classes on their
   semantic or refusal routes. A completed IME transaction may use the local route when its
   captured block-end anchor maps exactly to a zero-length source insertion. Concrete Release corpus evidence observed callback p95
   below 8 ms for every approved corpus case;
5. ✅ **COR-72 — Incremental Source pipeline.**
   Relexes invalidated lines until lexical state stabilizes and applies only matching bounded
   attribute patches. `SourceLexState` carries fenced-code state across CRLF/Unicode-safe
   `SourceLineIndex` ranges; superseded tasks are cancelled and stale patches apply nothing.
6. ✅ **COR-73 — Image identity and decode service.**
   Makes metadata identity the cache gate, decode a miss-only operation, and backing scale part of
   immutable request identity. `ImageDisplayServiceTests`, production-route telemetry, the full
   non-performance Debug suite, and the approved plan is
   deleted on delivery.
7. ✅ **COR-74 — Document files and lifecycle proof.**
   The corrected lifecycle suite exercises a real edit, saved-content revert, New controller route,
   two-window tabs, production Open Recent menu construction, and recent URL registration. The final
   full gate observed 514 tests passed, 50 production trace events,
   63 Done rows verified against 457 executed tests, and 31 increment rows resolved. The approved
   plan is deleted with delivery.
8. ✅ **COR-75 — Native Source editor and privacy contracts.**
   Proves native editing liveness and the offline/account-free/telemetry-free boundary without
   custom platform substitutes. The focused contract run observed 42 tests passed in 3 suites.
   The closing full gate observed 523 tests passed, 50 production trace events, 71 Done rows verified against 466 executed tests in 27
   cited suites, and 31 increment rows resolved after the review-proof corrections. The approved
   plan is deleted with delivery.
9. ✅ **COR-76 — Formal-GFM and Source contract.**
   Gives the pinned dialect one traceable fixture and range contract across parser, highlighter,
   projection, and encoder. The full gate passed with 528 tests, 80 Done rows verified against 471
   executed tests, and 50 production trace events. The approved plan is deleted with delivery.
10. ⚪ **COR-77 — WYSIWYG ownership, IME, selection, and undo.**
    ([plan](plans/COR-77-wysiwyg-ownership-ime-and-selection.md)) Closes native callback ownership,
    composition, selection, history, mode, and reconciliation through the transaction kernel.
11. ✅ **COR-78 — Image placement transaction.**
    All seventeen placement requirements are `Done` on observed proofs. The audit found the
    implementation sound and two genuine holes: REQ-062's bitmap-to-PNG fallback had no proof at
    all, and REQ-077 claimed symlinks, aliases, packages and non-regular sources were rejected
    while only symlinks were proved. Also added the case-variant collision proof REQ-067 needed
    and the ordering proof REQ-070 promised. `AssetDirectoryStore.directoryName` replaces the
    `assets` literal that was repeated at seven sites across two files.
12. ✅ **COR-79 — Diagnostics and process lifecycle.**
    REQ-097, REQ-098, REQ-101 and REQ-102 are `Done` on observed proofs. The audit found the alert
    and placement diagnostics already closed matrices, and one real hole: REQ-097's proof covered
    directory *resolution* but never the destructive half of its claim, so nothing showed a
    verification run could not prune the user's production diagnostics. It also found that
    `Scripts/test-verify-smoke-log.sh` — the nine rejected fixtures proving the smoke verifier
    still discriminates — had stopped being run by the gate when `check.sh` replaced
    `full-check.sh`; REQ-098's proof could have passed vacuously. Both closed.
13. ⚪ **COR-80 — Property testing and real corpora.**
    ([plan](plans/COR-80-property-testing-and-real-corpora.md)) Adds deterministic generators,
    shrinkers, independent oracles, and traceable CommonMark/GFM examples after core seams stabilize.
14. ⚪ **COR-81 — Accessibility, contrast, and display preferences.**
    ([plan](plans/COR-81-accessibility-contrast-and-preferences.md)) Gives every semantic and command
    route direct AppKit accessibility proof and closes color/preference policy. REQ-140 remains
    Deferred until a new platform API or separately approved product requirement exists.
15. ⚪ **COR-82 — macOS citizenship.**
    ([plan](plans/COR-82-macos-citizenship.md)) Characterizes already integrated window/shortcut work,
    then completes printing, command organization, list continuation, caret links, and window scope.
16. ⚪ **COR-83 — Release lifecycle and visual conformance.**
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
