# VISION

The durable product north star. This document states what the product is and what it optimizes
for. [ENGINEERING.md](ENGINEERING.md) is the authoritative current architecture;
[REQUIREMENTS.md](REQUIREMENTS.md) is the authoritative behavior contract.

## Product

A native macOS Markdown editor—pure and simple.

**Pitch:** *The Markdown editor that feels like it came with macOS.*

The app edits ordinary files rather than creating a library, workspace, account, private document
format, or cloud dependency.

## Objectives

In priority order:

1. **Trustworthy files.** A document remains an ordinary Markdown file that other tools can open.
2. **Correct editing.** Accepted input is never lost, duplicated, reordered, or applied somewhere
   other than the user's visible selection.
3. **Interoperable output.** Generated text follows a named, executable Markdown specification
   rather than an undocumented house dialect.
4. **No surprises.** Standard macOS document and editing behavior works as expected.
5. **Local and private.** Core editing is offline, account-free, and telemetry-free.
6. **Safe companion files.** Adding an image never overwrites, moves, alters, or deletes the
   source image or unrelated files.
7. **Fast and light.** Editing remains responsive with a small dependency and memory footprint.

When objectives conflict:

- preservation and correctness outrank convenience;
- visible, deterministic refusal outranks guessed mutation;
- standards-based source outranks renderer-specific decoration;
- a simpler ownership model outranks compatibility layers and duplicate state;
- measured behavior outranks architectural fashion.

## Product principles

- **The file is the truth.** No database, hidden identifier, base64 payload, or private metadata
  is required to understand a document.
- **Preserve unfamiliar source.** Unknown syntax remains visible and survives untouched.
- **Be precise about compatibility.** Standard Markdown syntax does not imply that every renderer
  supports every referenced media format. HEIC/HEIF is standard on Apple platforms but is not
  universally rendered elsewhere.
- **Prefer reversible behavior.** A failed operation may leave a recoverable unreferenced asset,
  but must not create a broken source reference or destroy existing data.
- **Ride the platform.** Prefer macOS document, text, accessibility, spelling, undo, drag, and
  paste behavior when it satisfies the requirements.
- **One obvious path.** Each state and operation has one owner and one production route.

## Editing experience

- The app has two genuine editors over the same Markdown source:
  - **WYSIWYG**, the default, shows formatted content without parsed Markdown delimiters.
  - **Source** shows and edits literal Markdown with live lexical styling.
- A visible toggle switches modes without rewriting the document.
- Both editors retain their own selection and scroll position.
- WYSIWYG text is ordinary visible content. Typing `*`, `_`, `#`, `|`, or another Markdown
  punctuation character inserts that literal character; it does not silently invoke formatting.
- Formatting is applied through the visible toolbar, native commands, and supported shortcuts.
- Task checkboxes are directly operable. Links are directly clickable and remain editable.
- Existing GFM tables render and allow cell-content editing. Table creation and structural
  row/column controls are outside the MVP.
- Unsupported or malformed syntax and raw HTML remain literal, unformatted, non-executing, and
  editable where an exact source mutation can be proven.
- Rich clipboard content pastes as plain text in the MVP.
- Source mode shows literal image syntax such as `![](assets/photo.heic)`. Image rendering belongs
  to WYSIWYG.

## Markdown compatibility

The MVP dialect is the complete **GitHub Flavored Markdown 0.29-gfm specification**: its bundled
CommonMark core plus tables, task-list items, strikethrough, extended autolinks, and tag
filtering. “GFM” means that published specification, not every feature on github.com.

Footnotes, `==highlight==`, superscript, subscript, definition lists, emoji shortcodes, heading
attributes, and smart-typography transformations are not part of the MVP dialect. Until a named
dialect profile is explicitly approved, such text is preserved without being presented as
supported semantics. Formal GFM strikethrough uses `~~double tildes~~`; `~single tildes~` remain
ordinary text.

Generated Markdown must pass focused fixtures derived from the named specification. A lexical
source highlighter is presentation, not proof of parser conformance.

## Images and companion assets

Users add images by pasting, dragging, or choosing **Add Image…**. There is no separate Import
command or second image pipeline.

- Added files go into a visible shared `assets/` directory beside the Markdown document.
- References use ordinary relative Markdown such as `![](assets/diagram.png)`.
- PNG, JPEG, GIF, HEIC, and HEIF files are copied byte-for-byte.
- HEIC/HEIF is never silently converted to JPEG or another representation.
- Bitmap-only clipboard data is encoded as PNG because no original file representation exists.
- References are inserted only after every destination file exists.
- Generated names are portable ASCII and never overwrite different existing content.
- Image descriptions initially remain empty and are selected for immediate authoring.
- The app emits no dimensions, raw HTML, title, base64 data, or private metadata.
- Undo and reference deletion affect Markdown only; assets remain in place.
- Save As, rename, and move preserve ordinary relative-path semantics and do not silently move or
  duplicate assets.

## Non-goals

- Notes library, graph, backlinks, proprietary sync, collaboration, account, or telemetry.
- Cross-platform application; the files themselves remain cross-tool.
- A claim that loose Markdown plus `assets/` forms an atomic package.
- Automatic asset garbage collection or remote-image downloading.
- Table construction or structural row/column controls in the MVP.
- Hidden delimiters, HTML/contenteditable, or rich text as the canonical document.

## Evaluation

A design is rejected if it fails source preservation, accepted-input correctness, standards
validity, non-destructive file handling, containment, accessibility, deterministic failure
behavior, or automated verification.

Designs that pass those gates are compared by:

1. correctness under rapid input, mode switching, undo, IME, and asynchronous reconciliation;
2. compatibility across Markdown tools and filesystems;
3. minimal prompts and configuration;
4. ownership clarity and absence of duplicate paths;
5. implementation and maintenance cost;
6. privacy and metadata consequences;
7. measured performance and concurrency safety; and
8. ability to add explicit dialect or asset workflows without migration.

Instrumentation never records document text, selected text, image descriptions, URL strings, or
complete local paths. Performance evidence records machine, software and build configuration,
corpus, sample count, median, and p95.

## Distribution

- Direct download, signed with a Developer ID and notarized by Apple.
- Not sandboxed for now. App Sandbox remains a future distribution decision.
