# COR-16 — Naming and layering cleanup

- **Status:** Approved; not implemented
- **Requirements:** none (no behavior change).
- **Architecture impact:** none; ENGINEERING §3 already states `EditorSession` is a state owner,
  not a view controller — this increment brings code into conformance with that existing rule.

No behavior change. Do this last so the smoke test and the instrumentation suites from COR-11–15
are in place to catch mistakes.

## Rename the coordinator namespaces

COR-10 deleted the `NSViewRepresentable` conformances from `MarkdownTextView` and
`WYSIWYGTextView`, leaving `enum` namespaces named after views that no longer exist. Residue of a
deletion is exactly what `CLAUDE.md` §2 forbids.

| Now | Rename to | File rename |
|---|---|---|
| `enum MarkdownTextView` | `enum SourceEditor` | `MarkdownTextView.swift` → `SourceEditor.swift` |
| `enum WYSIWYGTextView` | `enum WYSIWYGEditor` | `WYSIWYGTextView.swift` → `WYSIWYGEditor.swift` |

Nested `Coordinator` types keep their names, so references become `SourceEditor.Coordinator` and
`WYSIWYGEditor.Coordinator`. The `MarkdownSourceTextView` and `MarkdownWYSIWYGTextView`
`NSTextView` subclasses are **not** renamed — those are real views.

The project uses `PBXFileSystemSynchronizedRootGroup`, so renaming files on disk is enough; no
`project.pbxproj` edit is needed. Verify the build after renaming, and grep the docs
(`docs/REQUIREMENTS.md` names these types in "Implemented in" columns) and update them in the
same change.

## Move UI presentation out of `EditorSession`

`EditorSession.addImages()` calls `presentOpenPanel()`, which constructs and runs an
`NSOpenPanel`. Presenting UI from the type that owns editor state is a layering break:
`EditorSession` is a state owner per ENGINEERING §3, not a view controller.

Extract to `Markdown Editor/ImagePickerPresenter.swift`:

```swift
@MainActor
protocol ImagePicking: AnyObject {
    func pickImages() async -> [URL]
}

@MainActor
final class OpenPanelImagePicker: ImagePicking { /* the existing NSOpenPanel code */ }
```

`EditorSession` holds `var imagePicker: (any ImagePicking)?`, injected by `ContentView.onAppear`.
Delete the existing `pickImages` closure seam and `presentOpenPanel` in the same change — the
protocol replaces both, and leaving the closure would be a compatibility shim.

Check every test that sets `session.pickImages` and migrate it to a stub `ImagePicking`.

## Files

**Modify (rename):** `Markdown Editor/MarkdownTextView.swift` → `SourceEditor.swift`,
`Markdown Editor/WYSIWYGTextView.swift` → `WYSIWYGEditor.swift`, and every reference site.

**Modify:** `Markdown Editor/EditorSession.swift` (remove `presentOpenPanel`/closure seam, add
`imagePicker` property), `Markdown Editor/ContentView.swift` (inject `OpenPanelImagePicker` in
`onAppear`), every test referencing `session.pickImages`, `docs/REQUIREMENTS.md` (update
"Implemented in" columns naming the old type names).

**Add:** `Markdown Editor/ImagePickerPresenter.swift`, `sessionExposesNoAppKitPresentation` test.

**Delete:** `presentOpenPanel` and the `pickImages` closure seam on `EditorSession`.

## Proof

Existing suites must stay green — this is a pure refactor. Add
`sessionExposesNoAppKitPresentation`: a structural test asserting `EditorSession.swift` contains
no `NSOpenPanel`, `NSAlert`, or `runModal` reference.

## Rollback

Self-contained. File renames and the picker extraction can be reverted together; no other
increment in this initiative depends on these names.
