# COR-75 — Native Source editor and privacy contracts

- **Status:** Approved; not implemented
- **Delivers:** REQ-010, REQ-011, REQ-012, REQ-022, REQ-030, REQ-031, REQ-044, REQ-046
Architecture impact: none
Blockers: COR-68, COR-72
Executor: A junior may implement this plan from the closed matrix below; no product judgement is authorized.

## Scope

Prove the persistent Source editor behaves like a native text editor and that the product remains
offline, account-free, telemetry-free, appearance-adaptive, searchable, countable, and undoable.
Syntax styling mechanics belong to COR-72, not this increment.

## Files and ownership

- `SourceEditor.swift`, `MarkdownSourceTextView.swift`, `EditorSession.swift`,
  `MarkdownDocument.swift`, word/character count owner, app entitlements and project settings.
- Add `NativeSourceContractTests.swift` and `PrivacyBoundaryTests.swift`.
- Do not add an app-owned find panel, spell engine, account state, network monitor, or telemetry shim.

## Implementation

1. Directly construct the text view/coordinator/document and prove insertion, replacement, selection,
   Unicode, paste-as-text, undo/redo, continuous spell checking, standard find/replace action
   routing, word/character updates, and Light/Dark semantic color resolution.
2. Exercise every editing success route through the owner, not a pure helper. Undo/redo must restore
   source, selection, and revision exactly and remain document-owned.
3. Inspect linked frameworks, entitlements, URL-session/network symbols, account/auth storage,
   analytics SDKs, and diagnostic payload value types. Add a structural gate that fails on a newly
   introduced network/account/telemetry capability while allowing local file APIs.
4. Prove programmatic styling/count updates create no source edit or undo item, and stale count/highlight
   work applies nothing.
5. Fix only reproduced violations, deleting any displaced custom route.

## Failure and conformance

Every offered editing action has a liveness proof. Structural absence checks are rehearsed with a
fixture source that introduces a forbidden capability. No test drives UI. Source remains canonical
only through `MarkdownDocument`; native framework behavior is configured, not reimplemented.

## Deletion/conformance gate

Project/source inspection finds no app-owned find, spell, account, network, analytics, or telemetry
subsystem and no editor-local source/undo authority. The native command/action matrix and rehearsed
privacy fixture gate both pass.
