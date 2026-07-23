# RESEARCH-0004 — INC-03 image assets, source-mode boundary, and portability

- **Date:** 2026-07-23
- **For:** INC-03 (first-class images)
- **Type:** online research + repository architecture review
- **Status:** In progress — recommendations below require explicit approval before requirements,
  ADRs, or production code

## Question

How can a local-first Markdown editor import images through paste and drag-drop, keep those image
files beside their document, and remain maximally compatible with ordinary Markdown readers?

## Current constraints

- The document is one UTF-8 Markdown file managed by `FileDocument`; INV-2 requires that display
  behavior never silently rewrites unrelated source bytes.
- The app is direct-distributed and unsandboxed ([ADR-0004](../decisions/0004-direct-distribution-no-sandbox.md)),
  so it can manage sibling files without security-scoped bookmarks.
- The only delivered editing surface is live-styled **source** mode. Per the confirmed product
  boundary, it must display `![]()` source rather than replace it with an image attachment.
- WYSIWYG is INC-04, so image rendering is not an INC-03 source-editor behavior.

## Folder conventions and precedence

There is no universal macOS convention for a standalone `.md` file plus managed images. The useful
precedents are content-local rather than platform-specific:

| Convention | Precedent | Strength | Limitation for this app |
|---|---|---|---|
| Site-wide `assets/` or `assets/img/` | Jekyll static files | familiar for a website | mixes unrelated documents and creates ownership/collision ambiguity |
| Content-local resource directory | Hugo page bundles | resource travels with its page | Hugo uses a directory containing `index.md`, not a loose Markdown file |
| Per-document sibling folder | proposed `<document-stem>.assets/` | clear ownership; relative links survive moving the document and folder together | a user renaming only the Markdown file does not rename the folder |

**Recommendation, pending approval:** use a visible sibling folder named
`<document-stem>.assets/`, for example:

```text
Project/
├── meeting-notes.md
└── meeting-notes.assets/
    └── diagram.png
```

The generated Markdown stays ordinary and relative:

```md
![diagram](meeting-notes.assets/diagram.png)
```

This is not a proprietary container: other editors can read the Markdown and the referenced
files. It follows the content-local principle used by Hugo page resources while retaining a
standalone Markdown document. The app must not delete, rename, or garbage-collect files merely
because a reference changes; managed-file lifecycle needs its own explicit policy.

## Markdown image syntax and compatibility

The portable baseline is CommonMark image syntax:

```md
![Alternative text](relative/path.png "Optional title")
```

Relative destinations, alt text, and optional titles are standard Markdown. A generated image
reference in this form works in ordinary CommonMark/GFM readers, repositories, static-site tools,
and other editors.

Sizing is different. CommonMark/GFM has no standardized width/height syntax. Pandoc supports
attribute syntax such as `{width=480}`, but that is an extension; emitting it by default would
reduce compatibility. HTML `<img width>` is also widely rendered but is not portable Markdown and
may be stripped by renderers.

**Recommendation, pending approval:** INC-03 emits only standard `![]()` syntax and does not
serialize size. A future sizing feature should be researched and explicitly approved as one of:

1. a Pandoc/Markdown-Extra-style attribute extension;
2. raw HTML; or
3. editor-only display state that is deliberately not portable.

## Import mechanics on macOS

`NSTextView` supplies native drag destination behavior. Imports need more than file URLs:

- Finder and many Mail attachments provide `.fileURL`; copying the original file preserves its
  bytes and extension.
- Safari and Photos can provide `NSFilePromiseReceiver` promises; receive them asynchronously
  into the destination assets folder before inserting Markdown.
- Clipboard images can expose PNG or TIFF data without an original file. Prefer PNG for the
  generated fallback because it is broadly supported; preserve the original representation when
  the pasteboard provides a file URL or an identifiable image representation.

The receiving wrapper must obtain a destination path, write/copy the asset without blocking the
typing path, then insert source Markdown at the selection as one undoable edit. Multi-image drops,
filename collisions, unsupported formats, and failures require deterministic policies before
implementation.

## Decisions still required

1. Approve or change the `<document-stem>.assets/` naming convention.
2. Choose filename/collision policy: preserve source filename with deterministic suffixes, or
   generate editor-owned names.
3. Choose the initial accepted formats and the non-file clipboard fallback policy.
4. Confirm that INC-03 defers serialized sizing and WYSIWYG rendering as recommended.

## Sources

- [Hugo page bundles](https://gohugo.io/content-management/page-bundles/) and
  [page resources](https://gohugo.io/content-management/page-resources/) — content-local
  resources adjacent to a page.
- [Jekyll static files](https://jekyllrb.com/docs/static-files/) — common site-wide `assets/img`
  layout.
- [CommonMark image tutorial](https://commonmark.org/help/tutorial/08-images.html) — standard
  image source, alt text, and optional title.
- [Pandoc user guide](https://pandoc.org/MANUAL.pdf) — nonstandard image attributes such as
  `width` and `height`.
- [Apple: `NSTextView`](https://developer.apple.com/documentation/appkit/nstextview) and
  [file promises](https://developer.apple.com/documentation/appkit/supporting-drag-and-drop-through-file-promises)
  — native drag APIs and asynchronous promised-file receipt.
