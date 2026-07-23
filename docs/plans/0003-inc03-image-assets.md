# PLAN-0003 — INC-03 paste and drop images

- **Increment:** INC-03
- **Date:** 2026-07-22
- **Status:** Approved for a future build after COR-01
- **Requirements:** REQ-060–REQ-077
- **Depends on:** [PLAN-0004](0004-markdown-dialect-conformance-correction.md),
  [RESEARCH-0004](../research/0004-inc03-image-assets-and-portability.md),
  [ADR-0011](../decisions/0011-image-placement-and-portability.md),
  [ADR-0008](../decisions/0008-textkit1-nstextview-editor-engine.md)

## Goal

Let a user paste or drop supported images into a saved Markdown document. Copy file-backed
images unchanged into a visible sibling `assets/` directory, encode bitmap-only clipboard data
as PNG, and insert ordinary relative `![]()` source as one undoable edit only after every
destination exists. Preserve native non-image paste and drag behavior.

There is no “Import” command and no source-mode image rendering.

## Architecture

### `DocumentLocation`

Pass the current `FileDocumentConfiguration.fileURL` from `Markdown_EditorApp` through
`ContentView` to `MarkdownTextView`. Treat it as changing state rather than capturing it once.
It is `nil` for an untitled document.

### `ImagePlacementCoordinator` (`@MainActor`)

Own one user action:

- snapshot paste/drop items immediately;
- request Save when the document has no URL and resume only after it receives one;
- track the source selection with an edit-generation/range tracker;
- call the actor-backed placement service;
- cancel if edits overlap the tracked replacement range;
- commit ordered references as one `NSTextStorage` replacement and one undo group;
- select the empty description for a single result; and
- present one actionable error without consuming unrelated native input.

Only one placement transaction may commit to a given editor at a time. Later actions queue in
user order or fail explicitly; they do not race source insertion.

### `ImagePlacementService` (non-main actor)

Pure policy plus coordinated filesystem I/O:

- stage file promises under a private `mkdtemp`-equivalent directory;
- inspect regular-file status and Image I/O type;
- resolve and validate a non-symlink sibling `assets/` directory;
- slug names and select canonical extensions;
- hash only for deduplication/collision handling;
- reuse byte-identical regular files;
- copy new files with exclusive, non-overwriting creation under `NSFileCoordinator`;
- verify final containment and result type; and
- return ordered `PlacedImage` values only after all final files exist.

The service receives immutable values and does not retain pasteboard objects.

### Narrow AppKit input adapter

Extend the existing TextKit 1 wrapper:

- paste interception classifies the current pasteboard before calling the coordinator;
- mixed meaningful text plus image falls through to normal plain-text paste;
- drag interception accepts only supported image URLs/promises;
- all other drag and paste types call native `NSTextView` behavior.

Do not implement a second editor, invisible drop view, or custom document command.

## Policy details

### Supported representations

- File-backed `.png`, `.jpg`/`.jpeg`, `.gif`, `.heic`, and `.heif`: byte-for-byte copy.
- Bitmap-only pasteboard item: encode a PNG.
- Reject everything else with a clear format error.
- Detect representation from content with Image I/O, not extension alone.
- Never transcode HEIC/HEIF.

### Destination and names

- Destination is `<document-parent>/assets/`.
- Reusing a real existing directory does not establish ownership.
- Reject aliases, symlinks, packages, non-directories, and resolved paths outside the destination.
- Slug: lowercase ASCII alphanumeric; other runs become `-`; trim and cap; fallback `image`;
  avoid Windows device names.
- Check candidates case-insensitively.
- Reuse same-name identical bytes.
- For different bytes, append 12 lowercase SHA-256 hex characters, extending deterministically
  on a prefix conflict.
- Exclusive creation resolves time-of-check/time-of-use races; never overwrite.

### Generated source

```markdown
![](assets/photo.heic)
```

- no `./`, title, dimensions, HTML, base64, metadata, or percent-encoded filename;
- one line break between references in a multi-image action;
- preserve provider order;
- empty descriptions, with the sole description selected after a single insertion.

### Transaction and cleanup

Validate the entire batch before committing source. Insert no reference until all final
destinations exist. Before insertion, remove only staging files and newly created destinations
proven to belong exclusively to the failed transaction. Never remove reused or pre-existing
files. After insertion, undo edits source only.

If the insertion range is invalidated by an overlapping edit, cancel the source commit and
report that the image files were added but not referenced; do not guess a new cursor position.

### Save and move behavior

For an untitled document, start the normal Save flow, then resume. Canceling Save cancels the
pending placement without creating `assets/`.

Observe parent-directory changes. If generated `assets/…` references that previously resolved
become unresolved, present a non-destructive warning. Do not copy or move a shared directory
during Save As.

## Build steps and traceability

1. **Document URL plumbing** — implement REQ-060 and REQ-075–REQ-076; verify nil/current/changing URL
   behavior and Save continuation with coordinator tests.
2. **Pure representation and naming policy** — implement REQ-061–REQ-068; unit-test
   content detection, exact bytes, slugs, reserved names, dedupe, hashes, and references.
3. **Filesystem placement service** — implement REQ-065–REQ-071 and REQ-077; test exclusive
   writes, shared-directory reuse, containment, symlinks, failure cleanup, and races through a
   filesystem seam.
4. **Transactional source commit** — implement REQ-069–REQ-074; test ordering, one replacement,
   one undo group, description selection, tracked-range cancellation, and no file deletion.
5. **Paste and drag adapters** — implement REQ-060–REQ-064; test classification with
   pasteboard-value fixtures and adapter seams, including native fallthrough.
6. **Move warning and accessibility** — complete REQ-073 and REQ-075–REQ-077; test warning decisions and
   verify keyboard/VoiceOver labels through UI-accessibility tests where framework behavior is
   not inherent.
7. **Reconcile before PR** — change statuses and exact anchors in REQUIREMENTS, update ROADMAP,
   and record deviations in the living ADRs before review.

## Automated verification matrix

| Area | Required cases |
|---|---|
| Types | PNG, JPEG, GIF, HEIC, HEIF; mismatch; corrupt; unsupported |
| Fidelity | destination SHA-256 and bytes equal source for every file-backed type |
| Names | Unicode, punctuation, whitespace, empty, long, device names, case-only conflicts |
| Collisions | identical reuse, differing hash, digest-prefix extension, concurrent exclusive write |
| Paste | file URL, promise, bitmap only, text+image fallthrough, image+URL, stale snapshot avoided |
| Drag | URL, promise, ordered multi-image, non-image native fallthrough |
| Storage | existing assets, create assets, symlink, alias, package, permission, disk-full, partial batch |
| Transaction | no early reference, one insertion/undo, selection replacement, overlap cancellation |
| Lifecycle | untitled Save/resume, Save cancel, parent-change warning, undo/reference deletion retains files |
| Source | exact expected insertion; unrelated UTF-8/BOM/line-ending bytes unchanged |
| Concurrency | filesystem work off-main; UI/text mutation main-actor isolated |

Tests use temporary directories and fakes at pasteboard, Save continuation, and coordinated-write
boundaries. No requirement relies on manual verification.

## Risks and mitigations

- **HEIC/HEIF does not render everywhere:** preserve it by explicit product decision and state the
  media-compatibility limitation without changing source bytes.
- **File-provider races:** stage promises, coordinate writes, and use exclusive creation.
- **Shared-directory ownership:** never delete on undo or infer that an existing file is ours.
- **Async cursor drift:** track edits and cancel on overlap.
- **Pasteboard lifetime:** materialize immutable descriptors immediately.
- **Large images:** stream copy/hash where possible and never decode merely to copy.

## Out of scope

An Import command, file picker insertion, WYSIWYG rendering, thumbnails in source, image sizing,
transcoding, metadata stripping, optimization, remote downloads, garbage collection, automatic
asset relocation, and “Save a Copy with Assets.”
