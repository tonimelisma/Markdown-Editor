# COR-89 — Bounded authoritative rebuild

> **Status: proposed, not approved. Conditional — this increment may never be built.**

- **Executor:** an implementer who may exercise architectural judgement, with the user reachable.
  The largest change in the queue and the one most likely to be subtly wrong.
- **Blockers:** COR-86 (Release measurability) and COR-88 (oracle), both landed and observed.
- **Requirements moved to `Done`:** COR-86's new main-actor requirement, on observed Release
  evidence.
- **Architecture impact:** one new `ARC-###`. Needs explicit approval per `CLAUDE.md` §6.

## The decision gate

**Do not start this increment until COR-88 has landed and a Release measurement has been
observed.** Then, on every `PerformanceCorpus` case:

- **Within the 16 ms budget everywhere:** COR-86's requirement moves to `Done`, **this increment is
  not built**, and this file is deleted with a note recording that the architecture change was
  considered and measurement found it unnecessary.
- **Not within budget:** build what follows.

Committing to this gate in advance is the point. The measurement decides, not the appeal of the
design. Deleting a planned increment because evidence said so is a good outcome — and the one
`DECISIONS.md`'s cost argument would prefer.

## The defect, if the gate opens

After COR-88 the residue is genuine work: cmark parse (4.4–44.9 ms), projection model build
(0.0–53.3 ms), atom construction (0.0–26.7 ms) — all whole-document, for a command that changes
one block. On `heavyLists`, 18,519 of 18,520 blocks are byte-identical before and after a Cmd+B,
differing only by a fixed offset. Evidence:
`docs/research/2026-08-22-semantic-command-main-actor-cost.md`.

## Why the obvious fixes are band-aids

- **Extend `LocalTransitionDomain` to cover commands.** Rejected. That domain is deliberately
  closed, conservative, and parser-free; commands need exact semantic answers. Widening a safety
  boundary to buy latency inverts the product's stated conflict ordering.
- **Make commands asynchronous.** Rejected as stated: ENGINEERING forbids committing source while
  the projection is stale — *"It is forbidden to commit source and leave the old projection
  editable while waiting for parsing"* — and that rule is right. The variant that freezes the
  editor is honest but is a 180 ms freeze plus new UI state.
- **Cache the previous snapshot and diff.** That is COR-23, which exists at the *patch
  application* layer. The gap is one layer down.

## The proper fix

**Extend COR-23's principle from patch application to snapshot construction: structural sharing
across authoritative rebuilds.**

A `SourceMutation` carries an exact range. Given the previous snapshot and that range: blocks
ending before the mutation are reusable unchanged; blocks starting after it are reusable with a
fixed offset shift; only blocks intersecting the mutation, plus enclosing container context, need
reparse.

cmark parses whole documents, so the reparse operates on a **bounded window** — the outermost
enclosing top-level block plus a margin — spliced into the shared remainder.

**The correctness obligation is a single equivalence:**

> `splice(previous, parse(window), mutation)` is identical to `parse(wholeNewSource)`.

That is machine-checkable and the machinery exists. COR-80 built deterministic generators, a
bounded Markdown-aware shrinker, and imported 1,324 verbatim spec examples. The equivalence is a
**property over every spec example × every mutation class**, with the shrinker minimizing any
counterexample — exactly how COR-84's two lexer defects were found.

**Ambiguity refuses to optimize.** Where the enclosing window cannot be identified with
certainty — lazy continuation lines, a link reference definition outside the window, a fence
possibly opened elsewhere — the classifier returns "unbounded" and the code takes the existing
full-document path. The failure mode is *slow*, never *wrong*. This mirrors `LocalTransitionDomain`
and honors *"visible, deterministic refusal outranks guessed mutation"*.

## Files, types, and routes

**Add:** `Markdown Editor/BoundedRebuildDomain.swift` (pure window classifier + closed refusal
reasons); property cases in the COR-80 suites.

**Modify:** `AuthoritativePresentationBuilder.swift` (accept a previous snapshot and mutation;
choose bounded or full); `SemanticEditEngine.swift` (pass them); `PresentationSnapshot.swift`
(splice constructor).

**Delete:** nothing on delivery — the full path remains as the refusal fallback, which is a
declared route rather than a compatibility layer. If the property proves every case boundable,
that is a finding, not a licence to delete the fallback.

## Ordered phases

1. Re-measure in Release. **Apply the decision gate.** If within budget, delete this plan.
2. Classifier for boundable vs unbounded, pure, no parsing.
3. `boundedRebuildEqualsFullRebuild` over spec corpus × mutation classes. Expect counterexamples;
   each is either a classifier bug or a real projection defect. **Stop and re-plan on the latter.**
4. Splice construction; oracle validity preserved.
5. Wire into the command route.
6. Release evidence recorded in research.
7. `Scripts/check.sh`. Report actual output.

## Automated non-UI proof

- `boundedRebuildEqualsFullRebuild` over the spec corpus × mutation classes — the central property.
- `ambiguousEnclosureFallsBackToFullRebuild` — one case per refusal reason, closed set, so a new
  reason fails the build until its behavior is declared.
- `boundedRebuildPreservesOracleValidity` — COR-88's oracle validates spliced snapshots.
- Release corpus evidence: machine, build configuration, corpus, sample count, median, p95.

## Failure and rollback behavior

Every uncertain classification takes the full path, so a classifier bug costs latency, never
correctness. A splice that produces an oracle-invalid snapshot refuses as `.unprovable`, the
existing behavior. Rollback is reverting the commit; the full path is still present and is the
only path again.

## Deletion and conformance gate

No second parse route may exist outside `BoundedRebuildDomain`'s declared window: proved by the
closed refusal set plus a check that `AuthoritativePresentationBuilder` has exactly two callees.

## Risk

Highest-consequence increment in the queue. Two structural mitigations: the equivalence property
is checked against a **pinned external specification** rather than the app's own opinion, and
every uncertain case takes the old path, so the blast radius of a classification bug is latency
rather than corruption.
