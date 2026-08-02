# COR-34 — Attribute refresh escapes its semantic block

- **Status:** Approved; not implemented

## Scope

A one-word formatting command refreshes attributes across the **whole document** instead of the
semantic block it touched. Restore the bounded scope REQ-109 promises, and return REQ-109 to
`Done`.

This is finding 1 of the COR-32 investigation, split out because it is a different defect in a
different file from the suite hang: this one is a real product defect in
`PresentationPatch.attributeRefreshScope`; COR-32 is a test-harness hang.

## Reproduction

**Four** tests fail, not one. All four assert that an attribute refresh stays inside the semantic
block it touched, which is why one root cause explains all of them:

| Test | Cited by |
| --- | --- |
| `hiddenDelimiterCommandRefreshesAttributesWithoutReplacing` | REQ-109 |
| `taskToggleRefreshesOnlyItsSemanticBlock` | REQ-109 |
| `headingAndLinkCommandsRefreshOnlyTheirSelectedBlock` | REQ-109 |
| `resolvedImageRefreshesItsAttachmentOnlyWhenDisplayIdentityChanges` | (uncited — see COR-35) |

The fourth is not cited by any requirement, which is its own finding: it guards attachment
refresh scope and nothing in REQUIREMENTS points at it, so even a working proof-result gate
(COR-35) would not have reported it. Traceability is currently one-directional in a second sense
— every cited test must exist, but not every test must be cited.

The first, run in isolation, fails with:

```text
Expectation failed: harness.storage.attributeReplacements.allSatisfy {
    NSMaxRange($0) < (harness.textView.string as NSString).length
}: one-word formatting refreshed attributes outside its semantic block
```

Reproduced at `c90db74`, at `24341da`, and at `a4e170b` — the PR #29 merge whose description
claimed *"Debug 328 passed / 0 failed"*. It has therefore been failing for the entire period in
which REQ-109 has been marked `Done` citing it, hidden because the suite containing it never
completes (COR-32).

Source `"First paragraph.\n\nSecond paragraph.\n"`, bold applied to the projection range
`{0, 5}` — the word "First".

## Root cause (hypothesis, to confirm first)

`PresentationPatch.collectDifferences` compares the two snapshots' arrays **by index**:

```swift
let count = max(current.count, next.count)
for index in 0..<count {
    switch (current[index]?, next[index]?) { … }
}
```

Bolding one word splits one inline run into two ("First" strong, " paragraph." plain). Every
subsequent element is then compared against its neighbour rather than its counterpart, so from
the insertion point onward **every index mismatches**, including the untouched second paragraph's
run. `attributeRefreshScope` takes `min(location)…max(NSMaxRange)` over those ranges, so the
scope becomes the whole document and `AttributedPresentationBuilder.blockScope` faithfully
expands it to every block.

The guard above it — `current.renderedString == next.renderedString` — does not help: hidden
delimiters mean the rendered text is *identical* while the run array's **length changes**, which
is exactly the case index comparison cannot survive.

This was flagged during the August review as a latent weakness and dismissed because the
rendered-text guard appeared to prevent element counts from changing. That reasoning was wrong,
and this test is the counterexample.

Confirm before fixing: log or assert the computed scope for this exact input and show it equals
the whole document, and that `runs.count` differs between the two snapshots.

## Requirements and invariants

- REQ-109 → returns to `Done` when this is fixed. Currently `Correction`.
- REQ-107: semantic block treatments are unchanged by this; only the refreshed *scope* changes.
- ARC-019, ARC-Q16: an ordinary accepted edit applies one bounded patch and performs no
  full-storage replacement. A whole-document *attribute* refresh is not a full replacement, so it
  never tripped the full-replacement allowlist — which is why only this test saw it.
- REQ-090, ARC-Q05: a document-wide attribute refresh on every formatting command is also a
  latency defect on large documents; the fix should show up as reduced main-actor work.
- **Architecture impact: none.** `attributeRefreshScope`'s contract is unchanged — it must return
  the smallest whole-block scope whose presentation semantics differ. The defect is that it does
  not currently do so.

## Production route

Modify `Markdown Editor/PresentationPatch.swift`:

- `collectDifferences` — compare by **position in the projection**, not by array index. Both
  arrays are ordered by `utf16Range`/`projectionRange`, so walk them together and treat an
  element as changed when no counterpart covers the same range, rather than when the element at
  the same ordinal differs. Elements whose ranges match and whose equivalence closure returns
  true are unchanged regardless of how many elements precede them.
- Apply the same correction to every caller: runs, blocks, attachments, tables, and list markers
  all use this helper and all have the same failure mode.

No production type gains or loses a member; no other file needs to change.

## Implementation phases

1. Confirm the hypothesis: assert the computed scope for the failing input is the whole document
   and that `runs.count` differs. If it is something else, stop and re-diagnose — the fix below
   assumes this cause.
2. Correct `collectDifferences` to range-aligned comparison.
3. Verify `hiddenDelimiterCommandRefreshesAttributesWithoutReplacing` passes and that the
   adjacent scope tests (`sourceOnlyTableChangesDoNotExpandAttributeRefreshScope`,
   `resolvedImageLocationParticipatesInAttributeRefreshScope`,
   `resolvedImageRefreshesItsAttachmentOnlyWhenDisplayIdentityChanges`,
   `newerSnapshotWithUnchangedTextReplacesNothing`) still pass.
4. Reconcile REQ-109 to `Done`; delete this plan.

## Automated non-UI proof

- The existing failing test is the primary proof and must pass.
- Add a direct table test over `attributeRefreshScope` covering: an element **inserted** at the
  start, one **removed** from the start, one changed in the middle, and one changed at the end.
  Each must produce a scope bounded to the affected blocks, with an untouched trailing block
  provably outside it. This is the case the index comparison cannot express, so it discriminates.
- Assert the refreshed scope excludes a trailing block that is byte-identical and
  semantically identical in both snapshots.

## Instrumentation and performance evidence

No new trace event. Re-record the focused Release `nativeInputCallback` and
`authoritativeApplication` gates once COR-32 makes the suite executable: a formatting command on
the 100,000 UTF-16 corpus currently refreshes attributes across the entire document, so the fix
should measurably reduce main-actor work rather than merely satisfy an assertion.

## Failure and rollback behavior

If a range-aligned comparison cannot prove a scope for some element kind, that kind must fall
back to the **whole document** exactly as today and record `presentationRecovered`, so an
unprovable scope is visible rather than silently wide. Canonical source is untouched throughout;
this changes only which derived attributes are recomputed.

## Deletion and conformance gate

- Prove one comparison helper remains, used by all five element kinds — the defect must not be
  fixed for runs alone.
- Both gate scripts pass; both smoke scripts pass; delete this plan in the implementing change.
