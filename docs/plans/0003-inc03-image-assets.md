# PLAN-0003 — INC-03 image assets and portable source insertion

- **Increment:** INC-03
- **Date:** 2026-07-23
- **Status:** Draft — discovery only; not approved for implementation
- **Depends on:** [RESEARCH-0004](../research/0004-inc03-image-assets-and-portability.md),
  [ADR-0003](../decisions/0003-markdown-dialect-gfm-plus-writing-extensions.md),
  [ADR-0004](../decisions/0004-direct-distribution-no-sandbox.md),
  [ADR-0008](../decisions/0008-textkit1-nstextview-editor-engine.md)

## Goal

Make pasted and dropped images first-class file assets without breaking ordinary Markdown:
copy or receive the image into a document-local assets folder, then insert a standard relative
`![]()` reference at the source editor’s selection. Source mode remains source-only; it does not
replace the Markdown with an attachment, thumbnail, or inline image.

## Proposed approach — pending decisions

1. **Asset location:** resolve the saved Markdown document’s directory and create a visible,
   per-document `<document-stem>.assets/` sibling folder on first successful import.
2. **Import model:** accept file URLs and file promises from drag/drop. Copy original files when
   available; use a documented PNG fallback for clipboard-only bitmap data.
3. **Source insertion:** generate standard Markdown only:
   ```md
   ![alt text](document.assets/file.png)
   ```
   Insert it at the current selection as one undoable text change; never embed image bytes or an
   app-private identifier in the `.md` file.
4. **Editor bridge:** extend the existing TextKit 1 `MarkdownTextView` rather than add a second
   editing surface. Keep asynchronous import I/O outside the `NSTextView` editing callback.
5. **No sizing serialization:** do not emit `{width=…}`, raw HTML, or an app-private size token in
   INC-03. Revisit sizing only with an explicitly approved interoperability choice.
6. **No source-mode rendering:** keep `![]()` visible. WYSIWYG image rendering is an INC-04
   responsibility.

## Required decisions before requirements and code

- Folder convention: approve `<document-stem>.assets/` or specify another name.
- Naming/collision behavior: preserve source filename with a deterministic suffix, or generate
  editor-owned names.
- Supported initial formats and clipboard conversion behavior.
- Whether an unsaved document may import an image (recommended answer: prompt for a document save
  first, because a sibling folder cannot be located safely otherwise).

## Planned verification once approved

- Unit tests for deterministic asset path and relative Markdown-reference generation.
- Unit tests for filename collision resolution and source insertion text.
- Integration tests for source-string fidelity: importing inserts only the expected Markdown and
  never changes unrelated document bytes.
- Framework/integration seams for file promises and AppKit drag delivery, with error paths tested
  through import-service fakes where possible.

## Out of scope

WYSIWYG rendering, source-mode thumbnails/attachments, image resizing syntax, image transforms,
remote downloads, asset garbage collection, image export, and in-fence language highlighting.
