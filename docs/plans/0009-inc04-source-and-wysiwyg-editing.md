# PLAN-0009 — INC-04 Source and WYSIWYG editing

- **Increment:** INC-04
- **Date:** 2026-07-25
- **Status:** Implemented with corrections required — superseded for correction work by
  [PLAN-0010](0010-inc04-correction-program.md)
- **Requirements:** REQ-052–REQ-059, REQ-078–REQ-087
- **Depends on:** COR-03; COR-04 / [PLAN-0008](0008-cor04-nsdocument-migration.md);
  [RESEARCH-0007](../research/0007-document-model-and-wysiwyg-architecture.md);
  [ADR-0003](../decisions/0003-markdown-dialect-commonmark-and-formal-gfm.md);
  [ADR-0008](../decisions/0008-textkit1-nstextview-editor-engine.md);
  [ADR-0010](../decisions/0010-concurrency-highlighting-pipeline.md);
  [ADR-0012](../decisions/0012-transactional-descriptor-relative-image-placement.md);
  [ADR-0013](../decisions/0013-source-backed-rich-projection-and-semantic-edits.md)

> This plan implements the approved two-mode product. WYSIWYG is actual rich content with parsed
> Markdown control characters absent. Source remains literal Markdown. TextKit 2 is not reopened,
> HEIC/HEIF is never converted to JPEG, and no UI test is added or run.
>
> **Post-merge review:** the outer decision remains accepted, but the first implementation did
> not satisfy several invariants or verification gates. RESEARCH-0008 and PLAN-0010 are
> authoritative for COR-05/06/07. Statements below describe the approved INC-04 intent, not proof
> that every item is currently delivered.

## Goal

Deliver the MVP's default WYSIWYG editor and Source/WYSIWYG toggle over one `NSDocument` source.
Both modes are directly editable, share one semantic command/undo system, preserve unknown and
untouched Markdown, support the complete formal GFM 0.29 dialect, and retain native macOS input,
selection, Find, spelling, accessibility, links, tasks, tables, and local images.

## Non-negotiable invariants

1. Only canonical Markdown source is serialized.
2. Opening, parsing, projecting, switching modes, and saving without an edit changes no source
   byte.
3. Parsed Markdown delimiters do not exist in WYSIWYG storage.
4. Unknown, malformed, and raw-HTML source remains visible, literal, editable, non-executing, and
   preserved.
5. Every rich edit produces one bounded source transaction or a typed refusal; no rich-storage
   serialization or whole-document normalization exists.
6. Existing source spelling is retained whenever a safe patch exists. Regeneration is limited to
   one inline node, block, or table.
7. Parser/projection/image results apply only to their exact source/location version.
8. Source remains available after every parser, mapping, image, or semantic-edit failure.
9. Source and WYSIWYG use TextKit 1. AppKit objects never cross off-main boundaries.
10. Local PNG/JPEG/GIF/HEIC/HEIF display is read-only and bounded. There is no remote fetch,
    transcoding, metadata rewrite, or HEIC/HEIF-to-JPEG code path.
11. Paste, drag-and-drop, and “Add Image…” use COR-02's one placement transaction.
12. No UI automation or manual verification is used.

## Dependency gate

Adopt direct `swift-cmark` at exact revision
`5d9bdaa4228b381639fff09403e39a04926e2dbe`, which contains cmark-gfm
0.29.0.gfm.13 (`587a12bb54d95ac37241377e6ddc93ea0e45439b`).

Enable exactly:

- `table`;
- `tasklist`;
- `strikethrough`;
- `autolink`; and
- `tagfilter`.

Set `CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE`. Disable smart punctuation, table spans, alternate
table output, and every extra extension. The dependency is BSD-2-Clause with identified
permissive derived files.

Per the repository workflow, the Xcode package-reference change is a project-config commit directly
to `main` after this plan is approved and immediately before the app-code worktree. That commit
must build by itself and pin the resolved revision. Parser production use begins only on the code
branch; reverting the config commit removes the unused dependency if the build is abandoned.

## Architecture

### `MarkdownParser`

A narrow owned wrapper contains all C API use:

- create/configure/free a parser within one call;
- convert C nodes immediately into immutable Swift value nodes;
- copy literals, destinations, list/table/task metadata, and one-based UTF-8 source positions;
- expose no C pointers outside the wrapper; and
- return `Result<MarkdownTree, MarkdownParseFailure>`.

Parsing runs off-main on immutable source. cmark is synchronous and cannot cancel mid-parse, so
tasks check cancellation before/after parsing and discard stale versions. Full reparse is the
initial design: measured median was about 4.8 ms at 100 KB and 53 ms at 1 MB. Do not introduce a
piece table or second incremental parser without later evidence.

Every dependency update must run all 670 formal-GFM examples and 21 pathological cases. A
conformance failure blocks the update; regex never patches parser semantics.

### `MarkdownSourceIndex`

For each source version, map:

- parser UTF-8 line/byte columns;
- absolute UTF-8 ranges;
- Swift `String.Index`;
- UTF-16 `NSRange`; and
- WYSIWYG projection ranges/insertion anchors.

All conversion is bounds-checked. Invalid boundaries produce a typed mapping failure and literal
fallback, not clamping or guessing. The table delimiter/alignment row is table-level structural
source: cell text can patch locally, while alignment/column changes would rewrite the table.
Structural table controls remain deferred in MVP.

### `MarkdownProjectionModel`

Off-main parsing produces a `Sendable` projection model containing:

- rendered strings and semantic runs;
- stable node identifiers;
- source/projection ranges and insertion anchors;
- paragraph/list/table layout descriptors;
- task and image attachment descriptors;
- link destinations; and
- literal fallback runs.

It contains no `NSFont`, `NSColor`, `NSParagraphStyle`, `NSTextAttachment`, `NSImage`, or other
AppKit type.

On the main actor, `RichTextBuilder` converts that value model into an attributed string:

- Heading 1–6, emphasis, strong, strikethrough, code, links, paragraphs, breaks, block quotes,
  thematic breaks, ordered/unordered/nested/tight/loose lists, tasks, tables, and local images;
- `NSTextTable`/`NSTextTableBlock` for existing GFM tables;
- semantic attributes/attachment identifiers for commands and accessibility; and
- literal runs for HTML, unsupported syntax, malformed syntax, and failed subtrees.

Automated inspection asserts that source markers for headings, emphasis, links, images, lists,
quotes, fences, tasks, and table separators are absent from storage.

### `EditorSession`

One window-scoped observable session owns derived/transient state:

- active mode, defaulting to WYSIWYG;
- persistent Source and WYSIWYG TextKit 1 views;
- per-mode logical selection and scroll position;
- parse/projection task and accepted version;
- projection/source mapping;
- semantic command state; and
- bounded derived-image cache.

It owns no serialized source. Switching mode snapshots/restores logical selection/scroll and asks
the inactive view to apply the newest accepted document version. It never copies one view's
storage into the other.

### `SemanticEditEngine`

Pure value operations consume source snapshot/version, semantic selection, and command. They
return:

```swift
enum SemanticEditResult: Sendable {
    case transaction(SourceEdit, postEditSelection: LogicalSelection)
    case refused(SemanticEditRefusal)
}
```

Operations cover:

- insertion/replacement/deletion;
- bold, italic, strikethrough, inline code;
- link add/update/remove;
- paragraph and Heading 1–6;
- ordered, unordered, and task lists;
- indent/outdent and list continuation/termination;
- block quote and code block;
- task toggle;
- table-cell content;
- image description/destination; and
- image insertion intent.

Locality rules:

- patch text/destination/task markers directly;
- retain `_`/`*`, `__`/`**`, double tildes, bullet spelling, list numbers, link form, and code
  fence/run spelling when safe;
- choose a delimiter longer than content conflicts for new inline/code syntax;
- rewrite one heading/list/quote/code block for block conversion;
- rewrite one table only when unavoidable; and
- refuse ambiguous or stale mappings without mutation.

Every generated result is reparsed under the pinned formal-GFM configuration before commit in
tests. Production command generation uses the same proven helpers, not a second serializer.

### Toolbar and commands

The visible toolbar contains:

- Source/WYSIWYG mode;
- Paragraph/Heading 1–6;
- bold, italic, strikethrough, inline code;
- link;
- ordered, unordered, and task list;
- block quote;
- code block; and
- Add Image….

The same semantic commands work in both modes. Source-mode commands operate on the literal
selection through the document transaction engine. Command enabled/state values come from the
active semantic selection; unsafe/ambiguous commands are disabled or produce one typed refusal.
Formatting hotkeys may be added where they are standard, but no custom shortcut is an MVP gate.

### Tasks, links, and accessibility

Task attachments expose checkbox role, checked value, meaningful label, keyboard action, and one
semantic task-toggle command. Links carry native `.link` attributes, open directly through an
injected `NSWorkspace` URL-opening action with no scheme allowlist, and remain editable through
the explicit link command. Raw HTML remains non-executing.

The WYSIWYG view and attachments expose meaningful roles/labels/values. Images use authored
description text; an empty description is represented honestly and remains easy to edit. The
implementation retains native marked text/IME, spelling, Find, keyboard selection/editing,
copy, and document undo.

### Paste policy

Ordinary text paste chooses the plain-text pasteboard representation even when RTF/HTML is also
available. It never infers `**`, links, headings, lists, or other Markdown from rich styles.
Image-only/mixed-image classification continues through COR-02 exactly as today.

### Tables

Existing formal-GFM tables render through TextKit 1 native table blocks. Cell-content selection
maps to and patches the cell's exact source. Insert Table, row/column insertion/deletion,
alignment controls, and table-wide normalization are absent from the MVP command surface.

### Local images and Add Image

`LocalImageResolver`:

- accepts only local relative destinations resolved against the current document URL;
- never downloads remote URLs;
- reads source properties with Image I/O caching disabled;
- rejects corrupt or over-limit dimensions before full decode;
- creates a fit-to-editor thumbnail off-main with an explicit maximum pixel dimension;
- caches by source version, resolved URL/content identity, and display bound;
- evicts by bounded entry/cost policy; and
- returns value descriptors to a main-actor attachment builder.

PNG, JPEG, GIF, HEIC, HEIF, missing, corrupt, moved-document, stale-decode, and oversize cases
have deterministic placeholders/failures. Display never writes an image destination or generates
JPEG.

“Add Image…” presents an injected `NSOpenPanel` adapter restricted to supported image types.
Selected URLs become the same file-backed claims used by paste/drop and enter
`ImagePlacementController`. Source and WYSIWYG capture their active logical insertion intent
through the document interface. It is image placement, not Import.

## Implementation sequence

1. **Pin the dependency — REQ-054.**
   - Land the standalone project-config commit on `main`.
   - Add license attribution required by distribution.
   - Prove exact revision and enabled-option inspection.
2. **Build parser/source index — REQ-054/055/057/085/087.**
   - Wrap cmark C lifetime and produce Swift value AST.
   - Add complete conformance, pathological, Unicode, line-ending, BOM, malformed, source-slice,
     and cancellation/version tests.
3. **Build projection values and rich builder — REQ-054–REQ-056/080/084.**
   - Cover the complete dialect and literal fallbacks.
   - Inspect WYSIWYG storage for delimiter absence and correct attributes/mappings.
4. **Build semantic edits — REQ-057/058/078–REQ-080/083/087.**
   - Implement pure operations in small syntax-family modules.
   - Add before/after, changed-range, alternate-spelling, nested, Unicode, stale, refusal, and
     generated-source conformance tables.
5. **Build persistent mode host — REQ-052/053/058/083/086.**
   - Retain both TextKit 1 views and per-mode state.
   - Make WYSIWYG default; connect one mode control and document versions.
   - Route both adapters through document transactions/undo.
6. **Build toolbar/menu command model — REQ-058.**
   - Derive state/enabled values from semantic selection.
   - Connect Source and WYSIWYG without duplicated command implementations.
7. **Build tasks/links/tables/accessibility — REQ-078–REQ-080/084.**
   - Add semantic attachments/actions and native table blocks.
   - Test roles, labels, values, keyboard actions, URL routing, selection, IME, spelling, Find,
     paste, and undo using direct components.
8. **Apply plain-text paste policy — REQ-059/084.**
   - Centralize ordinary paste representation selection.
   - Preserve COR-02 image classification and native plain-text behavior.
9. **Build local image projection/cache — REQ-081/085/087.**
   - Add real PNG/JPEG/GIF/HEIC/HEIF fixtures and byte hashes.
   - Test bounded off-main thumbnails, cache eviction, corrupt/missing/oversize/remote/move/stale
     cases, and accessibility descriptions.
10. **Add “Add Image…” — REQ-082/083.**
    - Inject the picker result for tests.
    - Route both mode selections to COR-02 and prove provider order, overlap cancellation, single
      empty-description selection, source-only undo, and retained assets.
11. **Integrate and delete temporary seams.**
    - Remove any placeholder projection/editor code as each real subsystem lands.
    - Search for hidden delimiters, whole-document rich serialization, duplicate image pipelines,
      remote fetches, Image I/O destination/JPEG generation, and TextKit 2 use; none may remain.
12. **Reconcile before PR.**
    - Add REQ anchors to all code/tests; update requirement status/traceability and ROADMAP.
    - Keep parser revision/license and measured results current.

## Automated verification matrix

| Area | Required non-UI evidence |
|---|---|
| Parser | 670/670 formal-GFM examples; 21/21 pathological cases; exact extensions/options/revision |
| Source index | UTF-8/Swift/UTF-16/projected exact slices for ASCII, Unicode, emoji, combining marks, BOM, LF/CRLF, tabs, nested/multiline/malformed constructs |
| Projection | complete rich attributes/mappings; parsed delimiters absent; literal punctuation and unsupported source retained |
| Semantic edits | command × alternate-spelling before/after tables; exact changed unit; reparse validation; typed refusals |
| Modes | default WYSIWYG, persistent views, zero-change toggles, selection/scroll restoration, stale inactive-view rejection |
| Undo | Source/WYSIWYG typing, formatting, task, link, cell, and image sequences across mode switches |
| Native behavior | direct TextKit components for selection, marked text/IME, spelling, Find, paste, links, tasks, attachments, accessibility |
| Images | real PNG/JPEG/GIF/HEIC/HEIF hashes; off-main bounded decode; no destination/transcode/network; cache and failure matrix |
| COR-02 | entire existing suite plus editor-neutral Source/WYSIWYG/picker capture and commit |
| Performance | raw median/p95 for parse, index, projection values, main attributed application, edit translation, selection remap, image decode/cache |
| Concurrency | strict Swift 6; executor identity; cancellation; source/location version rejection; no AppKit off-main |

The existing Source and COR-02 suites remain green. No XCUITest target, screen automation, or
manual verification is permitted.

## Performance policy

This was the INC-04 performance policy. The user subsequently approved explicit correction
budgets in RESEARCH-0008 and PLAN-0010; those budgets supersede the no-threshold portion below.
The structural rules remain:

- native text insertion is the synchronous path;
- parsing/projection/image work is off-main and version-gated;
- full parse is initial policy;
- derived images are bounded/cached;
- stale work never blocks or overwrites newer source; and
- Source remains usable during degraded rich rendering.

Record production-corpus distributions during implementation. Do **not** introduce a
document-size degraded mode, parse/projection suspension, or styling cap for Source or WYSIWYG.
Any such threshold requires explicit product approval before becoming a requirement.

## Risks

- Source mappings can be invalidated by rapid typing: update bounded local mapping deltas for
  accepted native edits and serialize/refuse semantic actions until a matching projection exists.
- Rich projection replacement can disturb selection/IME: never replace storage during active
  marked text; remap logical selection and reject stale projection.
- Nested delimiters can be ambiguous: use parser context and typed refusal, not heuristics.
- Native table layout can be expensive: retain semantic table values and update only the affected
  table; measure real wide/long fixtures.
- Images can exhaust memory: inspect dimensions before decode, thumbnail off-main, bound cache,
  and keep original bytes outside derived state.
- cmark is C: confine pointer ownership to one wrapper, copy values immediately, and run fuzz/
  pathological/conformance gates on upgrades.

## Out of scope

- TextKit 2 or a third-party editor
- Additional Markdown extensions/dialect profiles
- Rich RTF/HTML-to-Markdown paste conversion
- Raw HTML execution
- Insert Table or structural row/column/alignment controls
- Remote-image download
- Image sizing syntax, transcoding, optimization, or metadata stripping
- HEIC/HEIF-to-JPEG generation
- UI tests or manual verification
