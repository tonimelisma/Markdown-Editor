# COR-61 — Every promise has a recorded way to break it

- **Status:** Approved; not implemented
- **Requirements:** REQ-138 (new, `Planned`); REQ-117, REQ-118 unchanged
- **ARC invariants:** ARC-027 (completed); ARC-Q22 (new)

## Context

`CLAUDE.md` §4 says: *"A green existing suite is not proof of a new claim. Tests must fail for the
relevant defective behavior before the fix or otherwise discriminate the required invariant."*

Nothing executes that sentence. It is a promise about the author's process, checked by review, and on
2026-08-10 it was discharged by:

```swift
// Verifies: REQ-124
@Test @MainActor func responsivenessProbeRecordsLatencyDistribution() {
    #expect(Bool(true))
}
```

Three of the six proofs cited by the new `Done` rows were literal tautologies. Two more were
tautologies wearing arithmetic (`UInt64 >= 0`) or reading the wrong thing entirely
(`everyWorkScopeIsOpenedByProduction` asserted `scope.symbol.rawValue.count > 0`). Each passed
`check-documentation-authority.sh` (the symbol resolves), would pass `check-proof-results.sh` (it
executes and passes), and carries a correct `// Verifies:` anchor. **Every existing gate is
satisfied by a test that cannot fail**, because every existing gate asks whether a proof *exists* and
*passes*, and a tautology does both perfectly.

This is the last and deepest instance of the pattern `CLAUDE.md` §4 has now recorded six times. The
only question that separates a real proof from a tautology is: *under what change to production code
does this test go red?* If the answer is "none", it proves nothing. So ask it mechanically.

## Architecture impact

`ARC-027` completed: with this increment, every class of proof obligation in the repository is
discharged by an observed execution. New quality scenario `ARC-Q22`.

## Production changes

No application code. New tooling and a new manifest.

### 1. `Falsification/REQ-###.json` — new, one file per `Done` requirement

```json
{
  "requirement": "REQ-109",
  "mutations": [{
    "rationale": "Full replacement instead of a bounded patch is the defect this requirement forbids.",
    "file": "Markdown Editor/PresentationPatch.swift",
    "find": "return .bounded(range: changed, replacement: replacement)",
    "replace": "return .fullReplacement(reason: .recovery)",
    "expect_red": ["newerSnapshotWithChangedTextUsesOneBoundedPatch", "tableCellEditUsesOneBoundedPatch"]
  }]
}
```

`find` must match **exactly once** in the named file, so a mutation cannot silently stop applying
after a refactor — it fails loudly instead, which is the behaviour that keeps the manifest honest as
the code moves.

### 2. Mutation quality rules, enforced structurally

A mutation must express a **plausible defect in the direction the requirement forbids**. The cheap
degenerate mutation — replacing a body with `fatalError()` — kills every test that touches the code
and proves nothing about discrimination. The gate rejects a mutation whose `replace` introduces
`fatalError`, `preconditionFailure`, `fixme`, `abort()`, or `while true`, or that deletes a function
body wholesale, or that spans more than five lines.

These rules narrow the failure mode; they do not eliminate it. Mutation *quality* remains a review
judgement, and this plan does not pretend otherwise — the honest claim is that after this increment a
tautology is structurally impossible to keep, not that every mutation is well chosen.

### 3. `Scripts/check-falsification.sh` — new

```
check-falsification.sh [--all | --changed <base>..<head>]
```

Per selected requirement: apply the mutation to a clean tree, build, run **only** the `expect_red`
proofs, require the build to succeed and at least one named proof to fail, then restore. Any of —
mutation does not apply, mutant does not compile, all named proofs still pass — is a failure of that
requirement's entry.

A mutant that does not compile is not a pass. It proves the compiler discriminates, not the test, and
the entry must be rewritten as a defect the type system permits.

`--changed` selects only requirements whose `Implemented in` files intersect the diff; this is the
per-PR mode. `--all` is the full sweep.

### 4. `REQUIREMENTS.md` gains the obligation

A `Done` row without a `Falsification/REQ-###.json` entry fails
`check-documentation-authority.sh`. This is what forecloses the tautology: REQ-124's cited proofs
cannot be made to fail by any mutation of `MainActorResponsivenessProbe`, so no valid entry can be
written for them, so the row cannot be `Done`.

## Phases

1. Manifest format, `check-falsification.sh`, fixture tests. No requirement entries yet.
2. Entries for the ~15 requirements most central to the architecture (`ARC-Q01`, `Q02`, `Q07`,
   `Q16`) — enough to prove the design on real invariants and to discover its friction before it is
   applied a hundred times.
3. Wire `--changed` into the PR gate set. Do **not** wire `--all` into `fast-check.sh`; see cost.
4. The remaining entries are COR-62's work, since authoring them *is* the audit.

## Automated proof

`Scripts/test-check-falsification.sh` (new, fixture-based, runs against a throwaway fixture package
rather than the real project, so it is fast and hermetic):

- an entry whose `find` matches zero times → fail;
- an entry whose `find` matches twice → fail;
- a mutant that does not compile → fail;
- a mutant that compiles and leaves every `expect_red` proof green → fail;
- a `replace` containing `fatalError` → fail (rejected by rule);
- a mutant that compiles and turns a named proof red → **pass** (liveness);
- a `Done` requirement with no manifest entry → fail.

**Rehearsal (`CLAUDE.md` §9):** author an entry for REQ-124 against the code as it stood at
`b241f9d` and confirm no valid mutation of `MainActorResponsivenessProbe` can turn
`responsivenessProbeRecordsLatencyDistribution` red. The inability to write a passing entry *is* the
gate working, and that demonstration belongs in the PR description.

## Instrumentation and performance evidence

None in the application. The gate's own cost is the significant number and is stated plainly:

| Mode | Scope | Estimated wall clock |
| --- | --- | --- |
| `--changed` on a typical PR | 1–5 requirements | 1–5 min |
| `--all` | ~100 requirements | 1.5–3.5 h |

Each mutation costs one incremental Swift build (~30–60 s) plus a focused test run (~5–20 s). `--all`
therefore belongs to a scheduled sweep and to the closing sequence of a release, never to the inner
loop. Wiring it into `fast-check.sh` would defeat the purpose of `fast-check.sh`, which exists
because a 25-minute inner loop gets run less often than a short one.

## Failure and rollback

The honest risks, recorded rather than discovered later:

- **Authoring cost dominates.** 100 entries at 10–30 minutes each of real thought is the single
  largest line item in this programme. COR-62 owns it and is scoped accordingly.
- **Mutation rot.** A refactor moves the code and `find` stops matching, failing the gate on a change
  that broke nothing. This is intended — an unmaintained mutation is an unverified requirement — but
  it is ongoing maintenance and will feel like friction.
- **Weak mutations pass.** A mutation targeting a trivial branch satisfies the gate without proving
  much. Only review catches this. If it becomes common, the next step is requiring two independent
  mutations per requirement, which doubles the cost; do not adopt that pre-emptively.

If phase 2 shows the friction is worse than estimated, stop before phase 4 and re-plan the corpus
strategy with the user. Do not silently reduce the rule to "warn": a warning-only falsification gate
is the same defect as a tautological test, one level up.

## Deletion and conformance gate

- Every `Done` row in `REQUIREMENTS.md` has exactly one `Falsification/REQ-###.json`.
- No `#expect(Bool(true))`, `#expect(true)`, or type-tautological comparison survives in any cited
  proof — a consequence, not a separate lint, since none of them can satisfy a mutation entry.
- `check-falsification.sh` is the single owner of mutation application; no test applies its own.
