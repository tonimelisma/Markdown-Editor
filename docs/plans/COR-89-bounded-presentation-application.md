# COR-89 — Bounded presentation application

> **Re-planned 2026-08-22.** This file replaces *COR-89 — Bounded authoritative rebuild*, whose
> premise Stage 0 falsified. That plan proposed reducing the parse/projection rebuild; the rebuild
> turned out to be 25–28 % of the command, so eliminating it entirely would still leave ~70 ms
> against a 16 ms budget. Recorded rather than quietly rewritten, per `docs/plans/README.md`: a
> plan that does not survive contact with the code is a finding.

**Executor:** an implementer who may exercise architectural judgement, with the user reachable.

**Blockers:** none remaining — COR-86 and COR-88 have landed. Phase 1 below is a measurement that
must complete before any design is chosen.

**Requirements:** closes REQ-143 (`Correction`).

## What is broken, and what is the evidence

A semantic formatting command blocks the main actor for up to 96.7 ms in Release on the approved
corpus, against a 16 ms budget. Evidence:
`docs/research/2026-08-22-semantic-command-main-actor-cost.md`, Findings 7 and 8.

What Stage 0 established:

- The authoritative rebuild — index, cmark parse, projection model, snapshot, oracle — is
  **26.9 ms of 96.7 ms** on `tableDense` and **26.5 ms of 94.6 ms** on `heavyLists`.
- After COR-88 the oracle is **0.00–1.14 ms**. It is no longer a target.
- A *full* attributed build costs 300.4 ms on `tableDense`, and a command costs 96.7 ms, so
  COR-23's bounded patch route is working — the command is not doing a full build.
- Attributed styling cost is driven by **block count, not character count**: ~12 µs per block,
  with the longest document (`degenerateParagraph`, 100,000 characters, one block) the cheapest at
  0.6 ms.
- Draining every `PerformanceSampler` metric after one command shows **only `semanticCommand`**.
  `authoritativeApplication` and `layoutApplication` do not fire on this path, so roughly 70 ms of
  the app's most expensive interactive operation is unattributed by its own instrumentation.

That last point is a defect in its own right and phase 1 fixes it first.

## Phase 1 — make the path self-describing, before designing anything

The remaining ~70 ms is known to be in presentation *application*, and not known to be in any
particular part of it. Three candidates, each with a different fix:

1. **Patch derivation** — `PresentationPatch` computes the difference between two whole snapshots.
   If this is O(blocks) with a large constant, the fix is to derive the patch from the mutation's
   known range rather than by comparing snapshots.
2. **Scoped attributed styling** — `AttributedPresentationBuilder.buildScoped` over the changed
   block range. At ~12 µs per block, this only matters if `blockScope` expands far beyond the
   edited block.
3. **`NSTextStorage` application** — `TextStorageApplier`, plus whatever TextKit does inside
   `beginEditing`/`endEditing` on a document with 24,400 `NSTextBlock`s.

**Do not choose a design before this measurement.** The previous plan was written from a Debug
phase table and named the wrong target; the honest lesson is that this path has repeatedly cost
its time somewhere other than where it looked.

Deliverable: `authoritativeApplication` and `layoutApplication` sampled on the command path — or,
if they are the wrong boundaries, new metrics that are the right ones — so the breakdown is in the
run log rather than in a temporary probe. Each new metric carries a budget, per `CLAUDE.md` §3.

## Phase 2 — the fix the measurement selects

Written as a decision table rather than a design, because phase 1 chooses between these and the
evidence does not yet exist. Whichever row is selected, the others are recorded as not taken.

| If phase 1 shows the cost is in | Then | Correctness obligation |
| --- | --- | --- |
| patch derivation | derive the patch from the `SourceMutation`'s known range instead of diffing whole snapshots | the derived patch equals the diffed patch, over the spec corpus × mutation classes |
| scoped styling / `blockScope` expansion | narrow the scope to the blocks the mutation actually touches | a scoped build equals the corresponding slice of a full build — the property `buildScoped` already claims |
| `NSTextStorage` / TextKit | apply the patch as one bounded edit, and re-examine whether a table needs one `NSTextBlock` per cell | laid-out line-fragment geometry is unchanged, per `CLAUDE.md` §3 |

**Ambiguity refuses to optimise.** Whatever bounding is introduced, a case that cannot be bounded
with certainty takes the existing whole-document path. The failure mode must be *slow*, never
*wrong*.

## What proof turns red if this is wrong

- `SemanticCommandBudgetTests.semanticCommandStaysWithinItsMeasuredCeiling` — the pinned ceilings
  drop as the fix lands; a regression past them reddens.
- `theBudgetIsNotYetMetAndIsRecordedAsCorrection` — reddens once every corpus is within budget,
  which is the signal to move REQ-143 to `Done`, delete the ceilings, and assert the budget
  directly.
- The equivalence property for whichever row phase 2 selects, over the imported spec corpus.
- Laid-out geometry proofs, if TextKit application changes.

## What must a human decide

- Whether row 3 is on the table at all: one `NSTextBlock` per table cell is an approved
  presentation decision in `ENGINEERING.md` §7, and changing it is an architecture change under
  `CLAUDE.md` §6, not an optimisation.
- Whether a corpus that no real document resembles should drive an architecture change.
  `tableDense` is 24,400 blocks in 29,280 characters — a table every 1.2 characters. `CLAUDE.md`
  §3 is explicit that a measurement describes only the input it was measured on, and REQ-090 was
  once satisfied by a corpus of one repeated word. **`structuredProse` at 40.2 ms is the case most
  likely to resemble a real document, and it is 2.5× over budget** — that alone justifies the
  work, and it may justify a different fix than the pathological cases would.
