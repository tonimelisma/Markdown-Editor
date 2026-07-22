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
| REQ-010 | The system shall provide plain-text editing of the document contents. | INC-01 | Done | `ContentView` (`TextEditor`) | inherent (framework-provided) |
| REQ-011 | The system shall support unlimited undo and redo of edits. | INC-01 | Done | `TextEditor` | inherent (framework-provided) |
| REQ-012 | The system shall integrate the macOS spell-checker. | INC-01 | Done | `TextEditor` | inherent (framework-provided) |

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

*Deferred to later increments:* find & replace (INC-02, needs the `NSTextView` surface),
live syntax styling / word count (INC-02), images (INC-03), WYSIWYG (INC-04).

*Next free IDs: REQ-008 (A), REQ-013 (B), REQ-023 (C), REQ-033 (D).*
