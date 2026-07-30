# INC-06 — Native command surface

- **Status:** Approved; not implemented
- **Kind:** App-code increment; one worktree, branch, PR, and squash merge
- **Requirements:** REQ-032, REQ-058, REQ-082, REQ-108
- **Architecture:** Implements ARC-024, ARC-Q20; preserves ARC-002, ARC-008, ARC-010
- **Depends on:** COR-18 and INC-05; COR-20 should land first so command timing/application uses
  the final edit route

## Goal

Replace the document-embedded formatting row with one window-scoped semantic command model,
native menu and `NSToolbar` presentations, shared validation, standard shortcuts, and a
window-attached link sheet.

## Baseline defects to reproduce

- At the default 720-point window, capture the current toolbar truncating Paragraph, list, Task,
  Quote, Code, and Add Image labels.
- Show formatting commands have no complete menu-bar equivalent.
- Show `promptLink` uses application-modal `NSAlert.runModal()`.
- Open two document windows and demonstrate why a global command target would risk crossing
  sessions; preserve this as a window-isolation test.

## Files

### Modify

- `Markdown Editor/ContentView.swift`
- `Markdown Editor/Markdown_EditorApp.swift`
- `Markdown Editor/EditorHost.swift`
- `Markdown Editor/EditorSession.swift`
- `Markdown Editor/DocumentActionInterface.swift`
- `Markdown Editor/Info.plist` only if native menu declarations require it
- `Markdown EditorTests/EditorIntegrationTests.swift`
- `Markdown EditorTests/AcceptedEditTransactionTests.swift`
- `Markdown EditorTests/ImagePlacementTests.swift`
- `docs/ENGINEERING.md`
- `docs/REQUIREMENTS.md`
- `docs/ROADMAP.md`

### Add

- `Markdown Editor/EditorCommand.swift`
- `Markdown Editor/EditorCommandController.swift`
- `Markdown Editor/EditorCommandValidation.swift`
- `Markdown Editor/EditorToolbarController.swift`
- `Markdown Editor/EditorMenuCommands.swift`
- `Markdown Editor/LinkEditorSheet.swift`
- `Markdown EditorTests/EditorCommandControllerTests.swift`
- `Markdown EditorTests/EditorToolbarConstructionTests.swift`
- `Markdown EditorTests/EditorMenuCommandTests.swift`
- `Markdown EditorTests/LinkEditorSheetTests.swift`

### Delete

- `Markdown Editor/EditorToolbar.swift`
- toolbar `HStack` and its divider from `ContentView`
- `NSAlert.runModal()` link editing
- direct menu/toolbar calls to `EditorSession.perform` outside the command controller
- any global notification or shared singleton command route
- this plan after implementation

## Command model

`EditorCommand` is a closed semantic enum covering:

- mode source/WYSIWYG;
- paragraph and Heading 1–6;
- bold, italic, strikethrough, inline code;
- link edit/remove;
- unordered, ordered, and task list;
- blockquote and code block;
- Add Image.

`EditorCommandController` is main-actor, window-scoped, and weakly bound to the current document,
session, action router, and presenting window. It provides:

- `availability(for:) -> enabled/disabled(reason symbol)`;
- `perform(_:) -> accepted/refused`;
- current mode/selection label state for toolbar/menu validation;
- link-sheet presentation state.

It computes one typed `EditorSelection` and one expected revision, then routes through the existing
semantic edit or image-placement transaction. Presentation objects never reconstruct selection.

## Toolbar

- Install one `NSToolbar` per document window.
- Default visible items:
  - mode segmented control;
  - paragraph/heading menu;
  - bold, italic, link;
  - structural-format menu;
  - flexible space;
  - Add Image.
- Optional/customizable items may expose strikethrough and inline code separately.
- Use native labels, SF Symbols where semantically clear, tooltips, accessibility labels, and
  `menuFormRepresentation`.
- Enable native overflow and autosaved customization.
- Do not place the toolbar inside document content.
- Validation delegates exclusively to `EditorCommandController`.

## Menu and shortcuts

Add a Format menu or equivalent native command group with every semantic command.

Approved shortcuts:

- Command-B: bold
- Command-I: italic
- Command-K: edit link

Do not invent shortcuts that collide with standard macOS document/edit commands. Menu items and
toolbar items must reflect identical enabled state for the active key window.

## Link sheet

- Present from the owning document window.
- Prepopulate the current destination only when exact selection semantics provide one.
- OK commits one `.setLink` command.
- Empty destination removes the link.
- Cancel changes nothing.
- Sheet closes if its owning document/session detaches.
- No application-modal alert and no cross-window state.

## Implementation

1. Add closed command/validation types and component tests.
2. Move current selection derivation out of `EditorToolbar` into the controller.
3. Route every existing formatting action through the controller.
4. Add menu commands and validate against the key document window's controller.
5. Add native toolbar/window installation and verify unique per-window ownership.
6. Add link-sheet state and presentation.
7. Move Add Image through the same command controller while retaining the one existing
   `ImagePlacementController` transaction.
8. Remove the SwiftUI toolbar row and old file.
9. Confirm editor content expands into the reclaimed vertical space and still obeys the reading
   column.

## Automated proof

- Every `EditorCommand` maps to exactly one production execution route.
- Menu and toolbar enumerate the same command identifiers.
- Validation tables cover Source/WYSIWYG, editable/waiting, exact/ambiguous selections, untitled
  documents, and detached sessions.
- Disabled commands cause no mutation even if invoked programmatically.
- Two-window tests prove commands and sheets never cross document/session/router boundaries.
- Command-B/I/K map correctly and do not replace standard unrelated shortcuts.
- Link sheet accept/remove/cancel paths are exact and window-scoped.
- Add Image uses the existing placement claim/transaction.
- Toolbar construction uses `NSToolbar`; no UI automation or pixel assertion.
- Accessibility labels exist for icon-only/grouped controls.

## Instrumentation

Reuse existing semantic mutation/refusal/image events. Do not add click/menu/toolbar telemetry.
Command origin may be a closed symbol only if it is required to diagnose routing and is approved
by the instrumentation vocabulary gate.

## Failure and rollback

- If no key document window/controller exists, menu command is disabled and performs nothing.
- A stale selection/revision refuses through the existing typed route.
- Cancelling/dismissing the link sheet performs no mutation.
- The old SwiftUI toolbar and new native toolbar must not ship together.

## Conformance and completion gates

- `rg "struct EditorToolbar|runModal\\("` returns no relevant production result.
- `ContentView` contains no formatting-control row.
- All formatting routes pass through `EditorCommandController`.
- ARC-Q20 passes.
- Full Debug/Release tests, gates, smoke, screenshot review, separate-agent review, PR triage,
  and stale-work cleanup pass.
- The screenshot shows untruncated document chrome at the default width.
- Reconcile REQ-058/108 only from proof; delete this plan.
