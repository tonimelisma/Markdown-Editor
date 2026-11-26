# ROADMAP

Delivery state and sequence. Implemented designs live in code, tests, [VISION.md](VISION.md),
[ENGINEERING.md](ENGINEERING.md), and [REQUIREMENTS.md](REQUIREMENTS.md) — not in a ledger here.
Git records the sequence; [DECISIONS.md](DECISIONS.md) records the choices that still bind.

**Status:** ✅ Delivered · 🔵 Active · ⚪ Planned · 🅿️ Parked

## What the app is today

The MVP behavior contract is complete: every row in [REQUIREMENTS.md](REQUIREMENTS.md) is `Done`
except two explicit `Deferred` rows. The application includes:

- ordinary UTF-8 Markdown documents through `NSDocument` — New, Open, Save, Save As, autosave,
  Versions, tabs, Recents, undo/redo, spelling, Find, and printing;
- formal GFM 0.29 parsing through pinned direct cmark-gfm, with a live-styled literal Source mode
  and a delimiter-free editable WYSIWYG mode over the same source;
- semantic formatting commands on one window-scoped command model with menu, toolbar, and
  shortcut parity; task, link, table-cell, and image interactions;
- exact-copy PNG/JPEG/GIF/HEIC/HEIF placement into a shared sibling `assets/` directory as one
  contained, non-destructive transaction;
- Swift 6 complete concurrency, privacy-safe local-only instrumentation, and per-run JSON Lines
  diagnostics whose payloads cannot represent document content;
- process-level smoke verification and a passive window-only screenshot verifier.

Two verification programmes closed before this queue opened: the **editor foundation rewrite**
(COR-18 – COR-31, typography, TextKit application, scheduling, native command surface) and the
**conformance and liveness programme** (COR-26 – COR-30, then COR-68 – COR-85, which audited every
requirement family against observed production evidence and closed the last two `Correction` rows).

## Now

Opened by a whole-repository review on 2026-08-22 that ran the full gate — 575 tests passed, 0
failed, smoke PASS — and then looked for what the requirement ledger cannot see. It found no
false `Done` claims. It found five things no requirement asks about.

| # | Increment | Objective | Blockers |
| --- | --- | --- | --- |
| COR-91 | ✅ Retire the planning apparatus | process | — |
| COR-86 | ✅ Release measurability and a bounded main actor | 7 | — |
| COR-88 | ✅ The oracle proves tiling, not coverage | 7 | COR-86 |
| COR-90 | ✅ Proof hygiene, launch surface, repository hygiene | 7 | — |
| COR-87 | ✅ External file truth | 1 | — |
| COR-89 | ✅ One rebuild and one parse per command | 7 | — |

Ordered by VISION's objective priority, not by discovery order: external file truth (objective 1)
precedes command responsiveness (objective 7). COR-86 leads only because it is small and
everything after it wants the measurement. COR-89 was re-planned twice. Stage 0 falsified its original premise — the rebuild it proposed to
bound is only 25–28 % of a command — and phase 1's instrumentation then found the real cause: the
same pure work ran repeatedly. The authoritative rebuild ran **three times** per command (twice as
validation) and the candidate text was parsed **twice**. Memoising both, deleting no validation and
computing nothing new, cut Release worst case by 3–8×.

REQ-143 is `Done`: the 16 ms budget binds on every corpus shape not declared a stress shape, and
`heavyLists` and `tableDense` carry recorded bounds instead. See `DECISIONS.md` for the criteria,
the rejected alternatives, and the respect in which the chosen one is worse.

**Every requirement is now `Done` except two explicit `Deferred` rows.**

## Next

**Packaging and distribution** (🔵 Active, 2026-11-26). Cloud-first development is in place:

- CI on GitHub's `xcode-27` runner;
- a Sparkle updater (REQ-033, REQ-034);
- a release workflow that publishes a signed disk image and the update feed for every `main`
  commit that changes the app (`DECISIONS.md`, 2026-11-26; `DEVELOPMENT.md`).

Still open:

- The five-minute budget. The first green run (CI 45855830007, 628 tests) took 5m12s from push to
  `CI gate`. Once the screenshot step stopped rebuilding the app, CI 45858255326 took about 4m50s,
  3m33s of it in `check.sh`, with an empty compilation cache. Measure again after the first merge
  saves that cache.
- An unexplained `mainActorStall` on CI. On CI 45856817544, the smoke run recorded two main-actor
  stalls over one second, and launch to exit took 11 s. The runs before and after it, on the same
  code, passed. The stall records were not kept then, so the cause is unknown. A failed smoke run
  now uploads its records (`smoke-records/` in `check-logs-*`). The next failure is to be read from
  them, not re-run.
- The first release, now that `SPARKLE_SEED` is set: it publishes with the next merge that changes the app.
- The first published release, and an installed copy seen updating itself. REQ-033 stays
  `Active` until then.
- Notarization, once a Developer ID exists.
- An app icon, a README and a LICENSE.

## Later — post-MVP backlog

Ideas, not commitments. Each requires research, explicit requirements, and approval.

- YAML front matter — the most common real-world construct the app currently renders as a stray
  thematic break followed by garbage prose
- Document-outline sidebar
- Named dialect profiles for footnotes, highlight, superscript, subscript, smart typography,
  definition lists, emoji, and heading attributes
- Mermaid diagrams
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
