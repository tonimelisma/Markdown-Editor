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
| COR-91 | 🔵 Retire the planning apparatus | process | — |
| COR-86 | 🔵 Release measurability and a bounded main actor | 7 | — |
| COR-87 | ⚪ External file truth | 1 | — |
| COR-88 | ⚪ The oracle proves tiling, not coverage | 7 | COR-86 |
| COR-89 | ⚪ Bounded authoritative rebuild — **conditional** | 7 | COR-88 (decision gate) |
| COR-90 | ⚪ Proof hygiene and harness containment | 7 | — |

Ordered by VISION's objective priority, not by discovery order: external file truth (objective 1)
precedes command responsiveness (objective 7). COR-86 leads only because it is small and
everything after it wants the measurement. COR-89 carries an explicit gate that can delete it —
if Release measurement after COR-88 comes in under budget, it is not built.

Evidence: [`research/2026-08-22-semantic-command-main-actor-cost.md`](research/2026-08-22-semantic-command-main-actor-cost.md).
Plans: [`plans/`](plans/).

## Next

**Packaging and distribution.** The engineering is finished and the product is not shippable: no
app icon, no README, no LICENSE, no CI, and no sign/notarize/staple/DMG path, against a VISION
that promises direct download signed with a Developer ID and notarized by Apple. Deliberately
sequenced after the queue above, while the app still has no users and changes are cheapest.

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
