# RESEARCH-0007 — Document model and WYSIWYG architecture

- **Date:** 2026-07-24
- **For:** SPIKE-02 → possible document-model migration → INC-04
- **Type:** repository analysis + online research + planned native-API/POC investigation
- **Status:** In progress
- **Outcome:** Preliminary recommendation: retain one canonical Markdown source and TextKit 1,
  but test macOS 27's reference-based SwiftUI `Document` protocol before building WYSIWYG.

> Research docs capture *investigation*, not decisions. A decision that comes out of research
> is recorded separately as an [ADR](../decisions/). Spike/POC code is throwaway (per
> [ADR-0005](../decisions/0005-discovery-and-build-are-separate-units.md)).

## Questions

INC-04 cannot be planned responsibly until the project answers:

1. Should the value-type `FileDocument` remain the document model once two editable surfaces,
   explicit semantic source edits, cross-mode undo, parser snapshots, direct file-location
   awareness, and image transactions all need stable shared state?
2. Can a genuine no-markup WYSIWYG editor be implemented on the already-selected TextKit 1
   `NSTextView` while keeping the Markdown string authoritative?
3. Which structural parser implements the approved CommonMark 0.31.2 plus formal GFM 0.29-gfm
   contract and supplies source positions precise enough for targeted edits?
4. What source representation may change after a WYSIWYG edit, and how narrowly can that change
   be bounded?
5. How should the landed COR-02 image transaction obtain an active source selection and commit
   Markdown without depending on the source view being visible?
6. What measurable performance, selection, undo, accessibility, and graceful-degradation
   behavior is achievable without UI automation?

## Approved product surface

The following is settled product direction, not an option for the spike to water down:

- The app has two editable modes over the same Markdown source.
- **Source mode** displays the literal Markdown characters with live source styling.
- **WYSIWYG mode** displays the parsed content with Markdown control characters absent—not merely
  made transparent—and permits direct rich-text editing.
- A visible mode control toggles between Source and WYSIWYG; WYSIWYG is the default.
- WYSIWYG provides a formatting toolbar. A selection can be made bold, italic, or otherwise
  formatted through native commands.
- Task-list checkboxes are interactive.
- Links are directly clickable.
- Formatting keyboard shortcuts are desirable but may be staged after the toolbar.
- If source has no supported Markdown semantics, WYSIWYG does not claim or invent formatting for
  it. The text remains visible and preserved.

Requirements and exact acceptance language still belong to the Specify step after SPIKE-02
resolves the engineering unknowns.

## Verified repository baseline

### Canonical source and document lifecycle

`Markdown_EditorDocument` is currently a `FileDocument` value with one stored `String`.
`ContentView` receives a binding to that value. `MarkdownTextView.Coordinator.textDidChange`
copies the source view's entire string back through the binding. File serialization is
`Data(text.utf8)`, which preserves valid unedited UTF-8, BOM, and line endings.

This satisfies today's single-editor implementation, but ADR-0006 already records the accepted
costs: awkward undo, no autosave-timing control, and a revisit trigger for undo fidelity,
large-file behavior, or external-change handling.

### Editor engine and concurrency

ADR-0008 selected TextKit 1 after a macOS 27 POC found TextKit 2's dynamic rendering attributes
unreliable and its viewport behavior problematic. The current source view is explicitly created
with `NSTextView(usingTextLayoutManager: false)`.

ADR-0010 is the app-wide editing/concurrency contract:

- AppKit objects stay on the main actor.
- Secondary computation uses immutable snapshots and `Sendable` values off-main.
- Results carry a monotonically increasing version and are discarded when stale.
- Native insertion remains the synchronous keystroke path.
- Source highlighting is debounced and suspended above 100,000 UTF-16 units.

SPIKE-02 must use TextKit 1 as its baseline. It does not reopen ADR-0008 merely because INC-04
needs rich text.

### Parser status

The current `MarkdownHighlighter` is deliberately lexical. ADR-0009 prohibits treating its regex
tokens as semantic parse results. No package dependency or structural parser exists.

ADR-0003 requires a WYSIWYG parser to be evaluated against exactly CommonMark 0.31.2 and formal
GFM 0.29-gfm. Unknown extensions must survive unchanged.

### COR-02 integration boundary

The merged COR-02 implementation replaces the defective image pipeline with a transaction state
machine and safe storage system, but its final main-actor controller still:

- holds a weak `MarkdownSourceTextView`;
- reads `selectedRange()` from that view;
- installs `InsertionRangeTracker` state on that view;
- finds the owning document for Save through the view;
- reads source from `textView.string`; and
- commits through `insertImageMarkdown`.

That is coherent for source-only editing. It is not an editor-neutral boundary for INC-04.
SPIKE-02 must preserve COR-02's transaction and storage invariants while determining how selection,
tracking, Save, and source commit move behind a shared document edit interface.

## Online findings

### macOS 27 document APIs

Apple's new SwiftUI `Document` protocol is reference-based and integrates with `@Observable`.
It provides direct document-URL access, coordinated file access, asynchronous readers/writers,
explicit actor boundaries, progress support, and manual undo registration.

Apple's migration guidance says `FileDocument` and `ReferenceFileDocument` remain available but
are no longer supported for new document types on macOS 27. The project already targets macOS
27.0. The new API is still marked beta, so adoption needs a real toolchain probe rather than a
paper decision.

`NSDocument` remains the mature fallback. It directly owns file location, Save completion,
autosave, Versions, window controllers, and undo, but would move substantially more document and
window infrastructure into AppKit.

### Text editing

`NSTextView` supports rich text, attachments, marked-text input, key bindings, selection,
spelling, paste, links, and undo. Those platform capabilities support a TextKit 1 WYSIWYG
prototype; they do not solve Markdown source mapping or source-preserving edit translation.

### Structural parser candidates

`cmark-gfm` is GitHub's C reference implementation for CommonMark plus formal GFM. It exposes an
AST and node source positions, passes the CommonMark conformance suite, and is fuzz-tested. A
direct, pinned Swift package wrapper is the leading candidate, subject to source-range probes.

`swift-markdown` wraps cmark-gfm and provides Swift value-tree APIs, but its current parser
configuration attaches table, strikethrough, and task-list extensions—not the complete formal-GFM
extension set—and enables smart parsing unless explicitly disabled. Its README also states that
its effective dialect may change. It cannot be adopted as the semantic authority without closing
those gaps.

`tree-sitter-markdown` explicitly warns that its output contains inaccuracies and is not
recommended where correctness matters. It may be useful for editor highlighting but is not a
candidate for the semantic authority required by ADR-0003.

## Architecture options

### Document model

| Option | Fit | Main risks | Preliminary assessment |
|---|---|---|---|
| Keep `FileDocument` | Lowest migration cost; existing byte-fidelity tests | Value rebinding, view-owned mutations, bespoke Save bridge, awkward cross-mode undo and URL lifecycle | Keep only if the new API probe fails or shows little concrete benefit |
| Adopt macOS 27 SwiftUI `Document` | Stable reference identity, `@Observable`, direct coordinated URL access, async I/O, explicit undo | Beta API and possible SDK churn; requires a migration | **Leading option; must be proven on the real toolchain** |
| Adopt `NSDocument` | Mature Save/URL/undo/autosave/Versions control | More AppKit document/window boilerplate; larger departure from SwiftUI-first | Stable fallback if the new SwiftUI API is unreliable |
| Adopt `ReferenceFileDocument` | Reference identity within older SwiftUI model | Deprecated for new macOS 27 document types; synchronous `FileWrapper` model | Reject |

### WYSIWYG representation

| Option | Source fidelity | Native editing | Assessment |
|---|---|---|---|
| Canonical Markdown + separate rich projection + targeted source edits | Preserves untouched source and unknown syntax | Uses `NSTextView`; owns mapping/edit translation | **Only option that satisfies the approved product and invariants** |
| Make AST/rich text canonical and serialize on Save | Normalizes whole documents and may discard unfamiliar syntax | Straightforward rich editing | Reject: violates INV-2/INV-7 |
| Keep literal source storage and hide/substitute delimiters at layout time | One storage, but complex character/glyph mismatch | Caret, selection, IME, attachment, and accessibility hazards | Reject |
| Web view/contenteditable | HTML-oriented model, conversion/normalization risk | Non-native undo, spelling, selection, accessibility, and file behavior | Reject |

The recommended projection is genuinely rich: its storage contains rendered characters and
attachments, not invisible Markdown delimiters. A separate mapping relates projection ranges to
source ranges.

### Transient versus persistent state

A blank-slate design should separate:

- **`MarkdownDocument`** — persistent canonical source, source version, file configuration,
  read/write snapshots, source-edit application, and undo registration; from
- **`EditorSession`** — active mode, per-mode selection/scroll state, parse task, current AST,
  projection mappings, and display-only resource cache.

Mode, selection, parse trees, and image caches must not become hidden document metadata.

## Preliminary recommendation

1. Use the merged COR-02 implementation as the code/test baseline.
2. Run SPIKE-02 as a standalone, throwaway POC and automated probe suite.
3. Keep TextKit 1 and the source-backed rich projection unless empirical evidence disproves them.
4. Prefer the macOS 27 SwiftUI `Document` protocol if it proves Save, URL, byte fidelity, undo,
   and two-editor integration on the real SDK.
5. Use `NSDocument` only as the evaluated fallback; do not migrate to deprecated
   `ReferenceFileDocument`.
6. Select a parser only after formal-dialect fixtures and source-range probes pass.
7. If the document-model probe selects a migration, perform it as its own approved build before
   INC-04. Do not combine infrastructure migration and WYSIWYG construction.
8. Write INC-04 requirements and its build plan only after the spike findings and remaining
   product decisions receive explicit approval.

## Remaining product decisions

SPIKE-02 must supply concrete examples and trade-offs before asking for final approval of:

1. **Normalization boundary:** preserve the existing spelling where a safe patch exists; when
   regeneration is unavoidable, choose the smallest permissible affected unit.
2. **Raw HTML:** display literal source versus render HTML semantics. The preliminary
   recommendation is literal, non-executing display.
3. **Rich paste:** translate the supported semantic subset of RTF/HTML versus paste plain text.
4. **Tables:** edit existing GFM tables only versus also provide an Insert Table workflow.
5. **Image command surface:** retain paste/drag-only placement versus add an “Add Image” file
   picker. There remains no Import document command.
6. **Source-mode toolbar:** keep semantic formatting commands active in both modes versus scope
   them to WYSIWYG.

## Sources

- [Apple — Creating a document-based app](https://developer.apple.com/documentation/swiftui/creating-a-document-based-app)
- [Apple — Updating your document-based app](https://developer.apple.com/documentation/swiftui/updating-your-document-based-app)
- [Apple — SwiftUI `Document`](https://developer.apple.com/documentation/swiftui/document)
- [Apple — `NSDocument`](https://developer.apple.com/documentation/appkit/nsdocument)
- [Apple — `NSTextView`](https://developer.apple.com/documentation/appkit/nstextview)
- [GitHub — cmark-gfm](https://github.com/github/cmark-gfm)
- [Swift — swift-markdown](https://github.com/swiftlang/swift-markdown)
- [swift-markdown parser configuration](https://github.com/swiftlang/swift-markdown/blob/main/Sources/Markdown/Parser/CommonMarkConverter.swift)
- [tree-sitter-markdown goals and accuracy warning](https://github.com/tree-sitter-grammars/tree-sitter-markdown/blob/split_parser/README.md)
- [CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/)
- [GitHub Flavored Markdown 0.29-gfm](https://github.github.com/gfm/)
