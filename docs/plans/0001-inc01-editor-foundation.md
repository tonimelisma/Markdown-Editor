# PLAN-0001 — INC-01 editor foundation (plain text)

- **Increment:** INC-01
- **Date:** 2026-07-22
- **Status:** Implemented — merged via PR #1 (squash `6211ecb`, 2026-07-22)
- **Requirements:** REQ-001…007, REQ-010…012, REQ-020…022, REQ-030…032
- **Depends on:** [RESEARCH-0001](../research/0001-inc01-editor-foundation.md),
  [ADR-0006](../decisions/0006-document-model-filedocument.md) (FileDocument),
  [ADR-0007](../decisions/0007-editor-surface-interim-texteditor.md) (TextEditor)

> Approved before code ([CLAUDE.md §3](../../CLAUDE.md)). This is the plan for the **build**
> unit that follows; it implements the approved requirements above and adds no new ones.

## Goal

A real, idiomatic plain-text Markdown editor: open/create/edit/save `.md` files with the
standard macOS document behaviors (autosave, Versions, tabs, Recents, Light/Dark), on
`FileDocument` + stock `TextEditor`. No syntax styling, find/replace, or WYSIWYG yet.

## Approach

- **UTType** — add `extension UTType { static var markdown: UTType { UTType(importedAs: "net.daringfireball.markdown") } }`.
- **Document (`Markdown_EditorDocument`)** — keep `FileDocument`; set `readableContentTypes`
  and `writableContentTypes` to `[.markdown]`; read `Data` → decode UTF-8, throwing
  `CocoaError(.fileReadCorruptFile)` on failure; write `text` back as UTF-8; default initializer
  produces an **empty** document (drop `"Hello, world!"`). Storing the file as a `String`
  preserves untouched bytes, including existing line endings and a leading BOM (no normalization).
- **Editor (`ContentView`)** — `TextEditor(text: $document.text)`; undo/redo and spell-check
  are provided by the framework.
- **Project config** — declare the imported type + document type (via build settings /
  Info.plist) so Finder and the Open panel recognize `.md`/`.markdown`. This is project-config
  → commits straight to `main`.

## Steps

1. Add `UTType.markdown`. → REQ-001 · *test:* resolves to `net.daringfireball.markdown`.
2. Update document read/write: UTF-8, invalid-UTF-8 throws, empty new doc, round-trip fidelity
   (incl. CRLF and BOM). → REQ-001/002/003/004/007 · *tests:* round-trip bytes, CRLF and BOM
   preserved, invalid-UTF-8 error, new doc empty.
3. Set `readable`/`writableContentTypes` + declare the document type in the project. → REQ-003
   · *verify:* Open panel lists `.md`; double-click opens.
4. `ContentView` plain-text editing. → REQ-010/011/012 · *verify:* type/undo/redo; spell-check.
5. Framework-provided behaviors: autosave, Versions, tabs, Open Recent, Light/Dark. →
   REQ-005/006/020/021/022 · *verify:* inherent (provided by DocumentGroup/FileDocument; no manual tests).
6. Confirm non-functionals: no network calls, no telemetry, VoiceOver/keyboard usable. →
   REQ-030/031/032 · *verify:* inspection + accessibility check.

## Testing

Unit tests target the document type (the testable core): round-trip fidelity, CRLF
preservation, invalid-UTF-8 error, empty-new-doc. Each carries `// Verifies: REQ-###`.
UI-level behaviors (tabs, Recents, autosave, appearance) are framework-provided and verified
`inherent` (no manual tests).

## Risks / open questions

- `FileDocument` papercuts (undo tracking, autosave timing) — accepted for now; revisit trigger
  in [ADR-0006](../decisions/0006-document-model-filedocument.md).
- Declaring document types via SwiftUI build settings vs a hand-written Info.plist can be
  fiddly; validate the Open panel + double-click flow early.

## Out of scope

Find/replace (INC-02), syntax styling / word count (INC-02), images (INC-03), WYSIWYG (INC-04),
the real text engine (SPIKE-01).
