# RESEARCH-0001 — INC-01 editor foundation (document model, UTType, text surface)

- **Date:** 2026-07-22
- **For:** INC-01 (plain-text editor foundation)
- **Type:** online research + native-API investigation (live SDK probe)
- **Status:** Done
- **Outcome:** Build INC-01 on `FileDocument` + stock SwiftUI `TextEditor`, opening
  `.md`/`.markdown` only via the system-declared `net.daringfireball.markdown` type. The
  real text engine is deferred to SPIKE-01; find/replace to INC-02.

> Investigation only. The decisions that came out of this are recorded as
> [ADR-0006](../decisions/0006-document-model-filedocument.md) (document model) and
> [ADR-0007](../decisions/0007-editor-surface-interim-texteditor.md) (editor surface).

## Questions

1. What Markdown `UTType` do we declare (the template ships a `com.example.plain-text` placeholder)?
2. Which document model — `FileDocument` vs `ReferenceFileDocument` vs `NSDocument`?
3. What text surface for INC-01, given SPIKE-01 (text engine) is scheduled *after* INC-01?
4. What do we get "for free" from `DocumentGroup`, and is autosave the TextEdit experience?

## Method

- Live SDK probe (`swift` one-liner against `UniformTypeIdentifiers`) to see how macOS 27
  resolves file extensions.
- Web research on the SwiftUI document APIs, their known papercuts, and `TextEditor` limits.

## Findings

**UTType (from the live probe):**

| Extension | Resolves to | Declared by system? | Conforms to `public.plain-text`? |
|---|---|---|---|
| `.md` / `.markdown` | `net.daringfireball.markdown` | yes | yes |
| `.txt` | `public.plain-text` | yes | yes |

→ No custom type needed. We **import** `net.daringfireball.markdown`; the placeholder is simply replaced.

**Document model:**

| Option | Type | Undo / autosave | Large files | Verdict |
|---|---|---|---|---|
| `FileDocument` | value (struct) | autosave + Versions free; undo tracking is awkward; can't tune autosave timing | whole file in memory | Simplest, idiomatic — chosen for INC-01 |
| `ReferenceFileDocument` | class | background autosave tied to `UndoManager` | still `FileWrapper`-based | More control, more complexity |
| `NSDocument` | class (AppKit) | full control | URL access, streamable | Most power, most boilerplate |

**Text surface:** stock SwiftUI `TextEditor` gained rich-text support in macOS 26 (we target
27) but still lacks the control needed for syntax styling and the system Find bar. An
`NSTextView` wrapped in `NSViewRepresentable` is more capable (native find/spell-check/undo)
but has state-sync pitfalls and would pre-judge SPIKE-01's engine choice.

**Free from `DocumentGroup`:** Finder integration; standard document menus (New / Open / Open
Recent / Save / Duplicate / Rename / Move / Revert); multi-window + document tabs; drag-and-
drop; iCloud/file-provider support.

**Autosave = TextEdit's behavior:** the system Auto Save + Versions (no manual Save, browsable
version history), inherited via `DocumentGroup`/`FileDocument`. Honors the system "Ask to keep
changes when closing documents" setting; `FileDocument` offers less timing control than
`NSDocument`.

## Recommendation

For INC-01: `FileDocument` + stock `TextEditor`; import `net.daringfireball.markdown`;
`.md`/`.markdown` only; UTF-8 with round-trip fidelity; defer find/replace to INC-02 and the
real engine to SPIKE-01.

## Open questions — resolved by the user (2026-07-22)

- Text surface → **stock `TextEditor`**.
- Document model → **`FileDocument`**.
- File types → **`.md`/`.markdown` only** (no `.txt`).
- Find/replace deferral to INC-02 → accepted.

## Sources

- [Apple forums — FileDocument vs ReferenceFileDocument](https://developer.apple.com/forums/thread/653546)
- [Eclectic Light — SwiftUI on macOS: Documents](https://eclecticlight.co/2024/05/16/swiftui-on-macos-documents/)
- [createwithswift — Crafting document-based apps](https://www.createwithswift.com/crafting-document-based-apps-in-swiftui/)
- [Swift Dev Journal — Document types in SwiftUI apps](https://swiftdevjournal.com/document-types-in-swiftui-apps/)
- [Artem Novichkov — Mastering TextEditor](https://artemnovichkov.com/blog/mastering-text-editor-in-swiftui)
- [Apple forums — NSViewRepresentable NSTextView](https://developer.apple.com/forums/thread/749620)
