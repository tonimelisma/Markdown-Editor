# REQUIREMENTS

The single source of truth for **WHAT** the app does. Requirements are **populated per
increment** during the discovery phase (the *Specify* step of [CLAUDE.md §3](../CLAUDE.md)).

## Conventions

- **ID:** `REQ-###`, assigned sequentially, never reused.
- **EARS notation** — UPPER-CASE keywords: `WHEN` (event), `WHILE` (state), `IF…THEN`
  (unwanted), `WHERE` (optional); otherwise a ubiquitous "The system shall …". One "shall"
  per requirement.
- **Status:** `Planned` · `Active` · `Done` · `Deferred`.
- **Traceability:** code carries `// REQ-###`, tests carry `// Verifies: REQ-###`
  ([CLAUDE.md §4](../CLAUDE.md)). Each row lists its code + verification anchors. `—` = not built.
- **Verification kinds (no manual tests, ever):** `test` = automated test (unit/UI) · `inherent`
  = satisfied by construction — either a standard framework component provides the behavior
  (e.g. `DocumentGroup` gives autosave/tabs) or code inspection proves it (e.g. "makes no
  network calls"). Nothing is verified by hand.
- **Forward:** every requirement has ≥1 verification (a `test`, or a justified `inherent`).
  **Backward:** every `REQ-###` in code exists here. A `Done` row has its verification recorded.

---

## INC-01 · Editor foundation (plain text) — ✅ Done

### A · Documents & files

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-001 | The system shall read and write documents as UTF-8 plain-text Markdown files with a `.md` or `.markdown` extension (`net.daringfireball.markdown`). | INC-01 | Done | `Markdown_EditorDocument` (`UTType.markdown`, `readable`/`writableContentTypes`) + `Info.plist` | test `readableAndWritableTypesAreMarkdown` |
| REQ-002 | WHEN the user chooses File ▸ New, the system shall create an empty untitled Markdown document. | INC-01 | Done | `Markdown_EditorDocument.init(text:)` | test `newDocumentIsEmpty` |
| REQ-003 | WHEN the user opens a `.md`/`.markdown` file, the system shall load its UTF-8 contents into an editor window. | INC-01 | Done | `Markdown_EditorDocument.init(data:)` / `init(configuration:)` | tests `roundTripsUTF8ContentUnchanged`, `readsEmptyFile` |
| REQ-004 | IF a file is not valid UTF-8, THEN the system shall report a read error and shall not open a corrupted document. | INC-01 | Done | `Markdown_EditorDocument.init(data:)` | test `invalidUTF8ThrowsReadError` |
| REQ-005 | WHEN the user edits a document, the system shall autosave changes without an explicit Save. | INC-01 | Done | `DocumentGroup` / `FileDocument` autosave | inherent (framework-provided) |
| REQ-006 | The system shall preserve macOS document Versions so the user can browse and revert. | INC-01 | Done | `FileDocument` Versions | inherent (framework-provided) |
| REQ-007 | The system shall save without altering bytes the user did not edit, preserving the file's existing line endings and encoding (INV-2). | INC-01 | Done | `Markdown_EditorDocument.init(data:)` / `data()` | tests `roundTripsUTF8ContentUnchanged`, `preservesCRLFLineEndings`, `preservesUTF8BOM` |

### B · Editing (plain text)

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-010 | The system shall provide plain-text editing of the document contents. | INC-01 | Done | `MarkdownTextView` (TextKit 1 `NSTextView`) | inherent (framework-provided) |
| REQ-011 | The system shall support unlimited undo and redo of edits. | INC-01 | Done | `MarkdownTextView` (`allowsUndo`) | inherent (framework-provided) |
| REQ-012 | The system shall integrate the macOS spell-checker. | INC-01 | Done | `MarkdownTextView` (`NSTextView`) | inherent (framework-provided) |

### C · Standard macOS behaviors

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-020 | The system shall support document tabs (multiple documents in one window). | INC-01 | Done | `DocumentGroup` | inherent (framework-provided) |
| REQ-021 | The system shall list recently opened documents under File ▸ Open Recent. | INC-01 | Done | `DocumentGroup` | inherent (framework-provided) |
| REQ-022 | The system shall adopt the system Light/Dark appearance automatically. | INC-01 | Done | system appearance (no overrides) | inherent (framework-provided) |

### D · Non-functional

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-030 | The system shall perform all editing offline, with no network access (INV-4). | INC-01 | Done | no networking APIs used | inherent (inspection) |
| REQ-031 | The system shall collect no telemetry and require no account. | INC-01 | Done | no analytics/account code | inherent (inspection) |
| REQ-032 | The system shall be operable via VoiceOver and full keyboard control (INV-6). | INC-01 | Done | stock SwiftUI controls | inherent (framework-provided) |

---

## INC-02 · Markdown engine + live-styled source — ✅ build (pending merge)

### E · Live-styled source

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| REQ-040 | WHILE in the source editor, the system shall apply live syntax styling as the user types, using display attributes that never modify the file bytes (INV-2). | INC-02 | Done | `MarkdownTextView.Coordinator.apply` | tests `attributeStylingLeavesStringUnchanged`, `rangesWithinBounds` |
| REQ-041 | The system shall style GFM elements: headings, bold, italic, inline code, fenced code blocks, links, images, ordered/unordered lists, task lists, blockquotes, tables, strikethrough, thematic breaks. | INC-02 | Done | `MarkdownHighlighter` + `MarkdownTheme` | tests `stylesHeadingWithLevel`, `stylesInlineElements`, `returnsAttributesPerStyle` |
| REQ-042 | The system shall style the light Tier-2 elements: footnotes, `==highlight==`, superscript, subscript. | INC-02 | Done | `MarkdownHighlighter` | test `stylesLightTier2` |
| REQ-043 | The system shall visually distinguish fenced code blocks (monospace + subtle tint). | INC-02 | Done | `MarkdownHighlighter` + `MarkdownTheme` | test `stylesFencedCodeBlock` |
| REQ-044 | The system shall display a live word and character count for the document. | INC-02 | Done | `TextStats` + `ContentView` | test `countsWordsAndCharacters` |
| REQ-045 | WHILE editing a large document, the system shall keep typing latency imperceptible (highlighting debounced and computed off the main thread). | INC-02 | Done | `MarkdownTextView.Coordinator` (off-main compute, debounce, size threshold) | inherent (by construction: keystroke path does only native insertion) |
| REQ-046 | The system shall support standard find and replace within the document. | INC-02 | Done | `MarkdownTextView` (`usesFindBar`) | inherent (framework-provided) |

*Reconciled:* REQ-010/011/012 (plain-text editing, undo/redo, spell-check) re-pointed from
`TextEditor` to the TextKit 1 `NSTextView` wrapper (`MarkdownTextView`).

---

*Deferred to later increments:* images (INC-03), WYSIWYG (INC-04), in-fence language
syntax coloring, remaining Tier-2 (definition lists, emoji, heading anchors).

*Next free IDs: REQ-008 (A), REQ-013 (B), REQ-023 (C), REQ-033 (D), REQ-047 (E).*
