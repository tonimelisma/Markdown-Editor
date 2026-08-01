# COR-23 — One patch route for every accepted WYSIWYG change

- **Status:** Approved; not implemented
- **Kind:** App-code correction; one worktree, branch, PR, and squash merge
- **Requirements:** REQ-109, REQ-058, REQ-090, REQ-103
- **Architecture:** Makes code conform to existing ARC-019 and ARC-Q16. No invariant changes.
- **Depends on:** COR-22
- **Must be last:** yes — closes the editor foundation rewrite

## Goal

Every accepted WYSIWYG change applies a bounded attributed patch. Today only native typing does.
Semantic formatting commands and authoritative reconciliation still replace the complete text
storage, which ARC-Q16 already forbids: it names initial load, recovery, and an explicit
typography change as the only full-replacement routes.

This is not an architecture decision. The architecture already says what must happen; the code
does not do it. Nothing in ENGINEERING changes except a statement of the reconciliation rule that
is currently unwritten.

## Baseline defect to reproduce

1. Attach a spy `NSTextStorage`, put the session in WYSIWYG mode with a current presentation, and
   perform `.toggleBold` through `EditorCommandController`. Show one `setAttributedString` over
   the whole document and zero bounded range edits.
2. Repeat for a heading change, a task-checkbox toggle, a committed link sheet, and a table-cell
   edit. All five take the same route.
3. Show why no existing test sees it: every spy-storage test drives `identityReplacement`
   typing, and every command-controller test runs in Source mode, where no presentation
   transition is produced at all.

Record the failing output in the PR before changing code.

## Cause

`SemanticEditEngine.planAuthoritativeTransition` sets `projectionReplacementRange` to the entire
presentation and `projectionReplacement` to the entire next rendered string. `EditorSession.perform`
installs that snapshot without building a patch, and `WYSIWYGEditor.Coordinator.applyProjectionIfNeeded`
applies any newer snapshot with `applyInitialPresentation`, a full replacement.

## Files

### Modify

- `Markdown Editor/PresentationPatch.swift`
- `Markdown Editor/TextStorageApplier.swift`
- `Markdown Editor/WYSIWYGEditor.swift`
- `Markdown Editor/MainActorWatchdog.swift` (proof only, see below)
- `Markdown EditorTests/TextStorageApplierTests.swift`
- `Markdown EditorTests/PerformanceBoundaryTests.swift`
- `Markdown EditorTests/EditorCommandControllerTests.swift`
- `Markdown EditorTests/ReconciliationInvariantTests.swift`
- `docs/ENGINEERING.md`
- `docs/REQUIREMENTS.md`
- `docs/ROADMAP.md`

### Delete

- the ordinary-edit dependence on a declared full-range `projectionReplacementRange`
- this plan after implementation

## Implementation

1. **Derive the changed span rather than trusting the declared one.** `PresentationPatch` gains
   `between(current:next:selectionAfter:buildScope:)`, which computes the real difference between
   the two rendered strings — common prefix, common suffix, adjusted to composed-character
   boundaries — and then expands to block scope exactly as today. `make(transition:…)` becomes a
   thin wrapper that validates transition identity and delegates, so both producers share one
   narrowing rule and one proof obligation (surrounding text identical in both snapshots).
2. **Let the view patch to a newer snapshot.** The coordinator keeps the applied
   `PresentationSnapshot`, not just its ID, so it can patch from it. When a newer snapshot
   arrives and the rendered text differs, it applies a patch. Marked text still suppresses any
   programmatic change.
3. **Reconciliation with unchanged text is an attribute refresh, not a replacement.** Replacing a
   provisional snapshot with an authoritative one usually changes attributes and not characters.
   Add `TextStorageApplier.applyAttributeRefresh`, which re-applies attributes over affected block
   ranges and mutates no characters. This keeps ARC-Q16's allowlist at exactly three
   full-replacement routes rather than adding a fourth.
4. **Refuse, never fall back.** A patch that cannot be proven takes the existing
   `presentationRecovered` route: typed reason, WYSIWYG unavailable, rebuild authoritatively.

## Automated proof

- Spy `NSTextStorage`, WYSIWYG mode, current presentation, for each of bold, heading, task
  toggle, link commit, and table-cell edit: exactly one bounded range edit, zero full
  replacements, resulting string equal to the next snapshot, selection and attachment lookup
  equal to a full rebuild's.
- Provisional → authoritative reconciliation with identical text: zero character replacements.
- Provisional → authoritative reconciliation with different text: one bounded patch.
- An unprovable patch records `presentationRecovered` and leaves source unchanged.
- Release: formatting-command latency on the 100k corpus, reported with the existing evidence
  helper. No new threshold is invented.

### Outstanding proof from COR-22

`MainActorWatchdog.probeOnce` was made `nonisolated` because a main-actor-isolated probe queues
behind the stall it exists to report. That fix currently rests on reasoning: the suite passed
with the isolation either way, so no test discriminates it. Land a test that fails when
`probeOnce` is main-actor isolated, or record in ENGINEERING that the property is argued rather
than proven. Do not leave it silently unproven.

## Failure and rollback

- If a formatting command's change cannot be narrowed to a provable span, it refuses through the
  existing typed route. It does not silently full-replace.
- If the attribute refresh cannot be made exact, stop and report measured options rather than
  reintroducing a full replacement under a new name.

## Conformance and completion gates

- A structural test proves the ordinary command path cannot reach `applyInitialPresentation`.
- ARC-019 and ARC-Q16 hold for commands as well as typing.
- Full Debug and Release suites, documentation-authority, instrumentation-coverage,
  `test-verify-smoke-log.sh`, `smoke-test.sh`, and a reviewed `smoke-screenshot.sh` capture pass.
- Separate-agent review, last-10-PR comment triage, and stale-work sweep pass.
- REQ-109 returns to `Done` only from this evidence; ROADMAP closes the rewrite program; delete
  this plan.
