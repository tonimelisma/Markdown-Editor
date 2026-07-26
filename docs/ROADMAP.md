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
- delimiter-free formatted WYSIWYG presentation and semantic formatting toolbar;
- task, link, table-cell, image-display, and image-placement interactions;
- exact-copy PNG/JPEG/GIF/HEIC/HEIF placement into a shared sibling `assets/` directory;
- Swift 6 complete concurrency and privacy-safe editor instrumentation.

The exact delivered/correction status of each behavior is recorded in
[REQUIREMENTS.md](REQUIREMENTS.md).

## COR-09 · Editor-state and projection consistency — `[build]` 🔵 Active

Correct the remaining editor-integrity defects without replacing the approved outer architecture.
Retain `NSDocument`, TextKit 1, two persistent native editors, pinned cmark-gfm, ordinary Markdown
source, and the existing image transaction.

The build will:

- replace parallel selection/view-state models with one typed session-owned state per mode;
- make each WYSIWYG presentation an indivisible revisioned snapshot;
- advance accepted source edits and their exact presentation transitions synchronously;
- reconcile authoritative parse/projection results asynchronously without exposing stale rich
  content as editable;
- separate literal WYSIWYG typing from semantic formatting commands;
- implement concrete source decoding/encoding for supported normalized representations;
- refuse unsupported, cross-cell, mixed-domain, or unprovable edits atomically;
- simplify document I/O to the default serialized `NSDocument` contract;
- make image-placement intent immutable;
- distinguish native user changes from programmatic selection/view updates;
- add discriminating non-UI state-machine, property, oracle, trace, concurrency, and Release
  performance evidence; and
- delete every displaced compatibility type and production route.

Approved implementation: [COR-09 plan](plans/COR-09.md).

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
- Themes and typography options
- Document-outline sidebar
