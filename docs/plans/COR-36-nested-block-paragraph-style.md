# COR-36 — A nested block discards its parent's indentation

- **Status:** Approved; not implemented

## Scope

A block nested inside another block inherits only its parent's `textBlocks`, not the rest of the
parent's paragraph style. A paragraph inside a list item therefore loses the list's hanging
indent, and the same applies to any block nested in a quote or list.

Raised by the separate-agent review of PR #33, which correctly identified it as **pre-existing and
out of scope for that PR** and did not report it as a defect of that change. It has not otherwise
been recorded, so it is planned here rather than lost.

## Reproduction, to establish first

Not yet reproduced with a failing proof — this plan's first phase is to write one. The reviewer
traced it statically at `AttributedPresentationBuilder` (the "containing blocks first,
`textBlocks`-only inheritance" mechanism), and the code path is unchanged from `main`.

Expected shape: a list item whose content is a paragraph node — for example a list item
containing two paragraphs, or a task item with a continuation paragraph — renders its second
paragraph flush to the reading margin instead of aligned under the item's text.

ENGINEERING §7 states the requirement directly: *"Blocks nested inside a decorated block inherit
its geometry instead of replacing it."* If the reproduction shows the geometry is in fact
inherited, this plan is deleted with that finding recorded, and the reviewer's static reading
was wrong.

## Requirements and invariants

- REQ-107: cumulative hanging indentation for lists, and the approved quote/code treatments.
- REQ-105: the approved typography tokens are unchanged; only inheritance changes.
- ARC-018: typography stays derived and never touches canonical source, history, or coordinates.
- ARC-Q15: constructed-container layout proofs at narrow, default, and wide widths.
- **Architecture impact: none.** ENGINEERING §7 already states the intended behaviour; this is a
  conformance defect against it, not a change to it.

## Production route

Modify `Markdown Editor/AttributedPresentationBuilder.swift`:

- The nested-block path currently copies `textBlocks` from the enclosing paragraph style and
  builds the rest fresh. It must instead start from the enclosing style and override only what
  the nested block genuinely redefines, so `headIndent`, `firstLineHeadIndent`, `tabStops`, and
  alignment survive.
- Interacts with COR-27's per-TextKit-paragraph installation: both concern which style a given
  paragraph ends up with, and both edit the same function. **Sequence COR-36 after COR-27** so
  the inheritance fix is written against the final shape of that code rather than being rewritten
  by it.

## Implementation phases

1. Write the failing layout proof. If it does not fail, stop and delete this plan with the
   finding recorded.
2. Change nested-block style derivation to inherit-and-override.
3. Verify quote, list, task, and code nesting at all three constructed widths.
4. Re-capture the REQ-104 screenshot; extend `Scripts/Fixtures/smoke-rich.md` with a list item
   containing a continuation paragraph so the visual gate can see this class at all — it
   currently cannot, which is why the defect survived every screenshot review.
5. Reconcile REQ-107 traceability; delete this plan.

## Automated non-UI proof

A laid-out-geometry proof of the kind COR-27 introduces, not an attribute-value assertion: force
layout on a directly constructed `NSTextView` and assert that a nested paragraph's line-fragment
origin is indented to its parent's content indent, and that an unnested paragraph at the same
depth is not. Assert the rendered string is unchanged (ARC-018).

## Instrumentation and performance evidence

No new trace event; no measurable latency change expected. Re-record the focused Release gates as
usual and treat movement as a finding.

## Failure and rollback behavior

If a nested block cannot derive a complete style from its parent, it must render with the
parent's geometry and no decoration rather than resetting to the document margin — losing
decoration is a smaller error than losing structural alignment. Source is untouched.

## Deletion and conformance gate

- Prove one nested-style derivation route exists; no second place may construct a nested block's
  paragraph style.
- Both gate scripts pass; both smoke scripts pass; the re-captured screenshot is reviewed;
  delete this plan in the implementing change.
