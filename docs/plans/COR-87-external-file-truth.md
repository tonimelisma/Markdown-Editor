# COR-87 — External file truth

> **Status: proposed, not approved.**

- **Executor:** an implementer who may exercise product judgement, with the user reachable. Step 1
  is discovery, and its outcome may change the matrix below. Not for an unattended agent: this is
  the only increment in the queue that changes behavior the user sees, in the area the product
  ranks first.
- **Blockers:** none. Independent of the whole performance track; can be taken first.
- **Requirements moved to `Done`:** none existing. Adds six new rows, `Planned` until observed.
- **Architecture impact:** one new `ARC-###`. Researched below; needs explicit approval per
  `CLAUDE.md` §6 before implementation.

## The defect

VISION objective 1 is *"Trustworthy files."* The product's whole thesis is that there is no
library and no sync: the user runs `git checkout`, edits in another editor, syncs a folder.

**No requirement covers what happens when the file changes underneath an open document.**
Searching REQUIREMENTS for external / conflict / changed-on-disk returns one hit, REQ-016, which
is about the app's *internal* stale-revision refusal.

`MarkdownDocument` overrides thirteen `NSDocument` members. None is `presentedItemDidChange`,
`presentedItemDidMove`, or `checkAutosavingSafety`. There is no `NSFilePresenter` code in the app
target; `NSFileCoordinator` appears only in `AssetDirectoryStore`, for asset copying.

`NSDocument` does provide real inherited behavior — it is a file presenter, and with
`autosavesInPlace` it reverts an unmodified document and raises a change-conflict alert on save.
So the app is probably not broken. **But "probably fine by inheritance" is what this repo refuses
everywhere else**: REQ-006 documents Versions as `inherent` and still cites two tests. The
highest-stakes file-trust scenario in the product has neither a requirement nor a proof, and
nobody has observed what the app actually does.

Two consequences are specific to this app and unlikely to be right by inheritance:

- **Two editors, two selections.** VISION promises *"Both editors retain their own selection and
  scroll position."* An inherited revert replaces text wholesale. Nothing preserves either
  editor's selection across an external reload.
- **Relative asset references.** VISION promises rename and move preserve relative-path
  semantics — specified for *in-app* moves. If the document is moved externally while open, every
  `assets/…` reference must re-resolve against the new parent. No test moves a document externally
  and re-resolves.

## Why the obvious fix is a band-aid

Overriding `presentedItemDidChange` and reloading silently picks one answer for a matrix of
situations. That is the "guessed mutation" this product explicitly ranks below "visible,
deterministic refusal".

## The proper fix

Model it as this repo models every other input surface: a **closed classification with a matrix
test that fails the build when a case has undeclared behavior** — the shape of
`LocalTransitionDomain`, `CommandLivenessMatrixTests`, `MarkdownAccessibilityModel`.

`ExternalChangeDomain`, a pure classifier over the closed product of document state × file event:

| | file changed | file deleted | file moved |
| --- | --- | --- | --- |
| **clean** | reload; preserve both selections by source offset | retain content; become modified-at-URL | follow; re-resolve asset base |
| **dirty** | retain local edits; mark conflicted; offer to reveal on-disk version | retain content; mark conflicted | follow; re-resolve asset base |

Commitments:

- **Never silently discard either side.** A dirty document never loses local edits to an external
  write, and an external write is never silently overwritten by the next autosave. Conflict is a
  visible state, not a race.
- **Reload preserves selection by source offset** where the offset still exists, clamping to the
  nearest valid boundary where it does not. `ProjectionCoordinateMap` and `SelectionAffinity`
  already solve this coordinate problem.
- **Deletion retains content.** Losing an open buffer because another process unlinked the file
  must be structurally impossible.
- **Every outcome reaches the run log**, as new `EditorTraceEvent` cases — the closed vocabulary
  already forces each to be declared. Payloads stay numeric/enumerated per REQ-031: an external
  change must never log a path.

## Files, types, and routes

**Add:** `Markdown Editor/ExternalChangeDomain.swift` (pure classifier + closed outcome enum);
`Markdown EditorTests/ExternalChangeTests.swift`.

**Modify:** `MarkdownDocument.swift` (file-presenter overrides, delegating classification —
the document is the only owner); `EditorSession.swift` (apply a reload while preserving
selections); `EditorTrace.swift` + `JSONLinesEditorTrace.swift` + `DiagnosticRecord.swift` (new
events); `ImageDisplayService.swift` / `AssetDirectoryStore.swift` only if step 1 shows the asset
base does not already follow `fileURL`; `docs/ENGINEERING.md`, `docs/REQUIREMENTS.md`.

**Delete:** nothing, unless step 1 finds an inherited path that must be displaced — in which case
it is deleted, not wrapped.

## Ordered phases

1. **Discovery, before any production change.** Write the six tests against **today's** inherited
   behavior and observe what they report. Record the results in `docs/research/`. Cells that
   inheritance already gets right become characterization tests and **no code is written for
   them** — the discipline COR-82 used for printing, tabbing, and frame autosave.
2. Present findings and the matrix; get approval for the new `ARC-###` and the requirement rows.
   **Stop here if approval is not given.**
3. Implement `ExternalChangeDomain` as a pure classifier with no filesystem access, so it is
   testable without I/O.
4. Wire the document's presenter callbacks to it. No editor adapter observes the filesystem.
5. Selection preservation across reload.
6. Asset base re-resolution on external move.
7. Diagnostics, then privacy proof.
8. `Scripts/check.sh`. Report actual output.

## Automated non-UI proof

Real filesystem tests against a temp directory; component-level, no UI automation.

- `externalWriteToCleanDocumentReloadsAndKeepsSelection`
- `externalWriteToDirtyDocumentKeepsLocalEditsAndMarksConflict`
- `externalDeleteRetainsContentAndCannotLoseTheBuffer`
- `externalMoveReResolvesRelativeAssetReferences`
- `everyExternalChangeClassHasDeclaredBehavior` — closed matrix; fails the build on a new case
- `externalChangeDiagnosticsCarryNoPath` — extends `PrivacyBoundaryTests`

What turns these red: removing a presenter override, changing a matrix cell without changing the
declared outcome, or letting a reload reset selection to zero.

## Failure and rollback behavior

Every classification has a declared outcome; there is no default branch. An unclassifiable event
takes the most conservative cell — retain content, mark conflicted — because retaining a buffer is
never destructive. Rollback is reverting the commit; the app returns to inherited `NSDocument`
behavior, which is the current state.

## Deletion and conformance gate

No editor adapter may observe the filesystem: proved by an absence check over the adapter files
with a self-verifying detector, in the style of `DisplayPreferencePolicyTests`.

## Risk

Highest-risk increment in the queue: the only one changing visible behavior, in the area with no
existing proofs. Mitigated by phase 1 — the current behavior is *unknown*, and discovering it is
cheap and cannot break anything.
