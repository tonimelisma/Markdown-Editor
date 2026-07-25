# RESEARCH-0008 — INC-04 correction architecture review

- **Date:** 2026-07-25
- **For:** COR-05, COR-06, COR-07
- **Status:** Approved
- **Scope:** Repository evidence, architecture alternatives, platform constraints, proof strategy
- **Decision:** Retain the product and outer native architecture; replace the defective
  transaction, source-coordinate, projection/edit, editor-host, and image-display internals.

## Question

After INC-04, is the selected architecture still the right foundation for a literal Source mode
and a delimiter-free editable WYSIWYG mode? If so, which parts need correction from first
principles, how can the claims be proved without UI or manual tests, and how should the work be
divided so a junior developer can implement it safely?

## Approved product facts

1. WYSIWYG is the default, delimiter-free, formatted, editable mode.
2. Source is literal Markdown with lexical formatting.
3. Both modes use one canonical ordinary Markdown source and a visible toggle.
4. The same formatting toolbar operates in both modes.
5. Unsupported, malformed, and raw-HTML source is literal, unformatted, editable, preserved, and
   non-executing in WYSIWYG.
6. Task checkboxes are directly operable. Links are directly clickable through `NSWorkspace`
   with no scheme allowlist.
7. Paste, drag-and-drop, and “Add Image…” share the COR-02 placement transaction. There is no
   Import command.
8. PNG, JPEG, GIF, HEIC, and HEIF originals remain exact copies. HEIC/HEIF is never converted to
   JPEG.
9. No UI automation or manual verification is permitted.

## Method

The review used four evidence classes:

1. **Current repository inspection:** production code, tests, requirements, plans, ADRs, and the
   merged INC-04 PR.
2. **Automated build evidence:** the normal non-UI test target and a forced Swift 6 complete
   concurrency build.
3. **Primary platform sources:** Apple documentation for `NSDocument`, `UndoManager`,
   `NSTextView`/`NSTextInputClient`, accessibility, Swift 6, Image I/O, `UTType`, and `CGImage`.
4. **Primary parser source:** the pinned cmark-gfm API and implementation for node source
   positions.

No production code was changed. The test-created `Markdown EditorTests/Fixtures/Images/doc.md`
was removed from the worktree after the run.

## Reproduced evidence

### Current green signal

This command passed:

```sh
xcodebuild test \
  -project "Markdown Editor.xcodeproj" \
  -scheme "Markdown Editor" \
  -destination "platform=macOS" \
  -only-testing:"Markdown EditorTests" \
  CODE_SIGNING_ALLOWED=NO
```

That result establishes that the existing test suite is green. It does **not** establish that
the WYSIWYG requirements are met: several tests assert only shallow examples, several behaviors
are marked inherent when custom code is responsible for them, and the suite omits known failure
sequences.

### Current red signal

This command failed:

```sh
xcodebuild build \
  -project "Markdown Editor.xcodeproj" \
  -scheme "Markdown Editor" \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_VERSION=6 \
  SWIFT_STRICT_CONCURRENCY=complete
```

Confirmed compiler errors:

- `MarkdownSourceIndex.swift:191`: a nonisolated context calls a main-actor-isolated custom
  `Result.flatMap`;
- `MarkdownSourceIndex.swift:206`: the same isolation failure.

The Swift 5 build also reports concurrency warnings in `EditorSession`, dead-code warnings in
`MarkdownSourceIndex`, and constructed-selector warnings in `Markdown_EditorApp`.

### Confirmed implementation defects

| Area | Repository evidence | Consequence |
|---|---|---|
| Undo | `MarkdownDocument.commitSourceEdit` captures one versioned inverse in its undo closure. | After a later edit, older undo closures submit a stale expected version; unlimited multi-step undo is not reliable. |
| Source positions | `MarkdownSourceIndex.utf8Range` treats equal start/end positions as empty. | A one-character inclusive cmark span can map to zero characters. |
| Projection mapping | `MarkdownProjectionModel.append` distributes a node source range over rendered UTF-16 units by index. | Delimiters, escapes, entities, attachments, and synthetic layout have guessed rather than semantic coordinates. |
| Selection mapping | `SemanticEditEngine.mapProjectionSelectionToSource` clamps both endpoints into the anchor array. | An invalid or stale selection can edit the wrong source instead of being refused. |
| Mode lifetime | `ContentView` conditionally constructs one `NSViewRepresentable` branch. | The inactive editor is destroyed; the persistent-editor and scroll-restoration requirements are not delivered. |
| Selection domains | WYSIWYG applies `MarkdownDocument.pendingSelection`, which is otherwise used as a source range, directly to rich storage. | Source and projection coordinates are conflated. |
| Window routing | `EditorSession.addImages` posts a process-wide notification and each `ContentView` subscribes. | An Add Image action can be received by multiple document windows. |
| Lists | Projection emits list children but no ordered or unordered marker. | Valid lists lose visible semantics in WYSIWYG. |
| Semantic commands | Block-prefix stripping and delimiter operations are regex/string heuristics with a small example matrix. | Nested structures and alternate valid spellings can be damaged or normalized too broadly. |
| IME | The adapter optimistically commits during native changes and only avoids projection replacement while marked text exists. | Composition ownership and its single undo transaction are not defined or proved. |
| Accessibility | Task activation is mouse hit-testing; keyboard press and a complete checkbox accessibility contract are absent. | REQ-032/078/084 are not proved. |
| Images | The test excludes HEIF; HEIC and HEIF fixtures are not meaningfully distinct; detected UTI is not validated; cache identity lacks file content identity and byte cost. | Format support, safety, freshness, and memory bounds are not proved. |
| Test hygiene | The image resolver test writes `doc.md` into the checked-in fixture directory. | A successful test dirties the repository. |

## Platform findings

### `NSDocument` and undo remain the right outer boundary

Apple defines `NSDocument` as the document-data, file-I/O, window-controller, and undo
architecture. `NSDocument` observes its `UndoManager`; undo registrations made while undoing form
the redo operation. The correct model is therefore one document-owned mutation path whose
history operation registers its inverse dynamically. Capturing a source version in a closure is
an implementation defect, not a reason to replace `NSDocument`.

Sources:

- [NSDocument](https://developer.apple.com/documentation/appkit/nsdocument)
- [NSDocument undoManager](https://developer.apple.com/documentation/appkit/nsdocument/undomanager)
- [UndoManager](https://developer.apple.com/documentation/foundation/undomanager)
- [NSDocument updateChangeCount](https://developer.apple.com/documentation/appkit/nsdocument/updatechangecount%28_%3A%29)

### Native `NSTextView` remains the right editing substrate

`NSTextView` already implements the text-input client contract. Marked text is transient text
with its own range and selection constraints; a projection replacement during composition can
invalidate that contract. The corrected adapter should let `NSTextView` own transient marked
text and commit one canonical mutation when composition finishes.

Sources:

- [NSTextInputClient](https://developer.apple.com/documentation/appkit/nstextinputclient)
- [Text input and marked text](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextEditing/Tasks/TextViewTask.html)
- [Setting focus and selection](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextEditing/Tasks/SetFocus.html)
- [NSTextView shouldChangeText](https://developer.apple.com/documentation/appkit/nstextview/1449532-shouldchangetext)

### Accessibility must be explicit for custom task controls

AppKit supplies accessibility for standard controls. Custom task attachments must expose the
checkbox role, label, value, and press action, including keyboard activation. A mouse override is
not an accessibility implementation.

Sources:

- [Accessibility for AppKit](https://developer.apple.com/documentation/appkit/accessibility-for-appkit)
- [NSAccessibilityButton](https://developer.apple.com/documentation/appkit/nsaccessibilitybutton)
- [accessibilityPerformPress](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol/accessibilityperformpress%28%29)

### Swift 6 is a correctness gate

Swift 6 complete concurrency checking turns potential data races into compile-time failures.
This project performs parsing and image decoding outside the main actor, so actor and `Sendable`
boundaries are part of correctness, not optional cleanup.

Sources:

- [Adopting strict concurrency in Swift 6 apps](https://developer.apple.com/documentation/swift/adoptingswift6)
- [Migrate your app to Swift 6](https://developer.apple.com/videos/play/wwdc2024/10169/)

### HEIC and HEIF should decode directly

Apple declares HEIC as `public.heic`, conforming to the broader `public.heif-standard`, and also
declares HEIF independently. Image I/O reports the detected type and can restrict the permitted
types per decode. `CGImage` is immutable and `Sendable`, so a bounded thumbnail can cross from
the decode task to the main actor without encoding an intermediate PNG or JPEG.

Sources:

- [UTType HEIC](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/heic)
- [System-declared UTTypes](https://developer.apple.com/documentation/uniformtypeidentifiers/system-declared-uniform-type-identifiers)
- [CGImageSource](https://developer.apple.com/documentation/imageio/cgimagesource)
- [kCGImageSourceAllowableTypes](https://developer.apple.com/documentation/imageio/kcgimagesourceallowabletypes)
- [CGImage](https://developer.apple.com/documentation/coregraphics/cgimage)

### cmark positions are necessary but not a complete editable projection

cmark exposes one-based start/end line and column values; its block implementation records an
end column for the last source line. These positions locate semantic nodes, but they do not by
themselves describe every rich insertion boundary, synthetic list marker, attachment, decoded
entity, or omitted delimiter. A lossless concrete-source layer must refine the semantic tree
into explicit editable and synthetic projection segments.

Sources:

- [cmark-gfm source-position API](https://github.com/github/cmark-gfm/blob/master/src/cmark-gfm.h)
- [cmark-gfm block source-position implementation](https://github.com/github/cmark-gfm/blob/master/src/blocks.c)

## Alternatives

### A — Keep the outer architecture and replace the defective core — selected

Retain:

- canonical Markdown in `NSDocument`;
- pinned cmark-gfm semantics;
- literal Source mode;
- delimiter-free WYSIWYG;
- two TextKit 1 editors;
- source transactions;
- COR-02 exact-copy image placement.

Replace:

- mutation/undo implementation;
- source-coordinate and projection representation;
- semantic edit planners;
- editor host and IME coordinator;
- document-window action routing;
- local-image display/cache implementation.

This preserves the product invariants and concentrates the rewrite where the evidence shows the
abstractions are insufficient.

### B — Make AST or rich text canonical — rejected

Saving would serialize an interpretation rather than the user's source. Unknown syntax, delimiter
choice, line endings, and untouched spelling could be normalized or lost.

### C — One literal storage with hidden delimiters — rejected

The text system would still navigate and compose over hidden characters. Caret, selection, Find,
IME, accessibility, and attachments would disagree with the visible content.

### D — HTML/contenteditable — rejected

This adds a Markdown-to-HTML-to-Markdown normalization boundary and gives up native AppKit text,
undo, spelling, accessibility, and document behavior.

### E — Reopen TextKit 2 — rejected

No newly demonstrated TextKit 1 requirement failure exists. TextKit 2 would not remove the need
for a lossless source projection or semantic edit translator.

### F — Patch current arrays and handlers — rejected

The current representation cannot distinguish a source-backed character, a synthetic character,
an exact insertion anchor, and an ambiguous location. More bounds checks cannot make an
insufficient model exact.

## Selected correction architecture

1. **Document mutation engine:** one content-validated `SourceMutation` path; dynamic reversible
   `HistoryPatch`; monotonic revisions on edit/undo/redo; explicit selection and grouping.
2. **Lossless source-coordinate model:** every projection segment is exact source, synthetic,
   literal fallback, or uneditable; every boundary maps exactly or refuses.
3. **Projection compiler:** cmark semantics plus concrete-source delimiter/content resolution;
   no proportional distribution.
4. **Semantic planners:** separate inline, block, list, table-cell, and link planners; reparse and
   validate every generated change before commit.
5. **Persistent editor host:** one window-scoped AppKit host owns both TextKit 1 views for the
   window lifetime and switches visibility/focus only.
6. **IME coordinator:** `NSTextView` owns transient marked text; one final source mutation is
   committed when composition finishes; stale composition refuses safely.
7. **Window-owned actions:** injected placement action replaces the global notification.
8. **Direct image display:** bounded off-main `CGImage`, actual-UTI validation, content-aware and
   decoded-cost-bounded cache; no derived PNG/JPEG encoding.

## Proof and instrumentation strategy

The redesign is accepted only through falsifiable evidence:

- characterization tests that reproduce each current defect before replacement;
- `EditorTrace` events for transaction ID, revision, mapping result, composition state, stale
  result, and timing—never document text or full paths;
- `os_signpost` intervals for parse, index, projection, rich construction, image decode, and
  main-actor application;
- a `ProjectionOracle` that proves all ranges are in bounds and every rich boundary is exact,
  synthetic with policy, or refused;
- reviewed golden fixtures for source, rich text, projection segments, command, and exact result;
- deterministic seeded mutation/property tests over formal-GFM, Unicode, CRLF, nested, malformed,
  and fallback cases;
- a temporary test/debug shadow comparison between old and new engines, adjudicated by the
  oracle rather than by treating the old result as correct;
- pure composition-state tests and direct AppKit component tests, never UI automation;
- optimized-build performance measurements with machine/build metadata.

Approved initial budgets:

| Metric | Gate |
|---|---|
| synchronous keystroke translation | p95 < 8 ms |
| persistent mode toggle | p95 < 16 ms |
| parse + source index + projection at 100,000 UTF-16 units | p95 < 100 ms, off-main |
| stale async result application | zero |
| decoded local-image cache | hard maximum 64 MiB |
| parser or image decode on main actor | zero |

If a budget is not reproducible on the recorded baseline machine, implementation stops and the
evidence returns to discovery; the developer does not weaken the gate silently.

## Approved delivery

Deliver three sequential build corrections:

1. **COR-05 — Source integrity and Swift 6**
2. **COR-06 — Exact projection and semantic edits**
3. **COR-07 — Persistent native editing and interaction completion**

Affected requirements return to `Correction` until their corresponding build and proof gate
passes. See [PLAN-0010](../plans/0010-inc04-correction-program.md).
