# COR-59 — Delivery status is derived, not written

- **Status:** Approved; not implemented
- **Requirements:** REQ-136 (new, `Planned`); REQ-117, REQ-118 unchanged
- **ARC invariants:** ARC-027 (strengthened)
- **Executor:** any agent. Shell and documentation; no Swift.
- **Expect rejected rows.** Phase 2 runs the gate against existing history and will reject rows
  beyond the ten known ones. Each rejection is a finding to record in ROADMAP, not a nuisance to
  edit around.

## Context

`CLAUDE.md` §3 says an implemented plan is deleted in the implementing change. On 2026-08-10 that
rule was run backwards: ten plans were deleted by commits containing nothing but a comment, and the
reconcile commit `64cadae` — whose message reads *"Fixes batch stub commits that deleted plans but
left ⚪ markers and plan links"* — inferred delivery from the absence of the plan file and flipped
all ten ROADMAP rows to ✅.

No gate objected, because no gate connects a ROADMAP row to evidence. `check-documentation-authority.sh`
verifies the *converse* — that a `Done` requirement is not contradicted by an increment ROADMAP still
lists as 🔵 active — but a ⚪ row silently promoted to ✅ names no requirement at all, so there is
nothing to contradict. Ten increments were reported delivered while citing zero requirements and zero
proofs, and every check passed.

The fix is to stop letting the status column be prose. **A ✅ must be derivable from evidence, or it
must not be writable.**

## Architecture impact

`ARC-027` strengthened: delivery status becomes a derived value over `REQUIREMENTS.md` and the run's
own results bundle. No application code, no runtime contract.

## Production changes

### 1. Plans gain a `Delivers:` header

`docs/plans/README.md` gains the requirement; every existing plan gains the line. The restored
COR-44..COR-55 plans already name their requirements in prose under **Requirements:** — this
formalises it into one machine-readable field, listing only the requirements the plan is expected to
move to `Done`, not every requirement it touches:

```markdown
- **Delivers:** REQ-123, REQ-124, REQ-125, REQ-126
```

A plan that delivers no requirement — a pure refactor such as COR-42 or COR-43 — declares
`- **Delivers:** none (refactor; no requirement changes status)`. That is a legitimate and common
case, and forcing it to be declared is the point: it cannot be reached by omission.

### 2. ROADMAP rows gain their requirement set

Every numbered increment row in an "Active" or "Delivered" section carries the same field, so the
ROADMAP row and the plan agree or the gate fails:

```markdown
3. ⚪ **COR-46 — One document build per keystroke.** (delivers REQ-090, REQ-109, REQ-123) …
```

### 3. `Scripts/check-delivery-status.sh` — new

For every ✅ row:

1. its `delivers` set is non-empty or explicitly `none`;
2. every named requirement exists in `REQUIREMENTS.md` and is `Done`;
3. every such `Done` row's cited proofs were **observed passing** in the current results bundle —
   by delegating to the existing `check-proof-results.sh` correlation rather than reimplementing it;
4. no plan file for that increment remains in `docs/plans/`.

For every ⚪/🔵 row: a plan file exists and is linked, and none of its `delivers` requirements is
already `Done`.

**Plan deletion is gated by the same run.** A commit that deletes `docs/plans/COR-NN-*.md` must, in
the same commit, leave every requirement in that plan's `Delivers` set `Done` and proven. A plan
deleted by a commit containing no production change fails, which is precisely the 2026-08-10 shape.

Fails closed: unparseable ROADMAP, zero resolved rows, or an absent bundle is a failure.

### 4. Wire into `fast-check.sh` and the full-run path

Runs after `check-proof-results.sh`, since it consumes the same bundle.

## Phases

1. Add `Delivers:` to `docs/plans/README.md`, all nineteen plans, and every ROADMAP increment row.
2. Write the gate; run it against current `main` and record every row it rejects.
3. Reconcile the rejected rows — each is either a false ✅ or a missing citation, and both are
   findings worth recording in ROADMAP rather than quietly fixing.
4. Wire into the gate set; rehearse failing.

## Automated proof

`Scripts/test-check-delivery-status.sh` (new, fixture-based, run by `fast-check.sh`):

- a ✅ row naming a requirement that is `Correction` → fail;
- a ✅ row naming a requirement that is `Done` but whose proof did not execute → fail;
- a ✅ row naming no requirements and no `none` declaration → fail;
- a ✅ row whose plan file still exists → fail;
- a ⚪ row with no plan file → fail;
- a ✅ row with `Delivers: none` and no plan file → **pass** (liveness: refactor increments must
  remain expressible);
- a fully consistent fixture → pass.

**Rehearsal against the real defect (`CLAUDE.md` §9):** run the gate against `64cadae`. All ten
promoted rows must fail — they name no requirements, their plans were deleted by commits with no
production change, and REQ-123..128 were `Done` on proofs that never executed. A gate that passes
`64cadae` has not closed the class and must not be trusted.

## Instrumentation and performance evidence

None. Documentation-layer gate.

## Failure and rollback

The gate is only as good as the `Delivers` sets, which are hand-written — a plan that under-declares
still passes. That residual is real and is recorded here rather than hidden: this increment makes a
*false* ✅ unrepresentable, not an *incomplete* one. COR-61's falsification manifest is what makes
the underlying `Done` meaningful; this gate only guarantees the ROADMAP cannot claim more than
`REQUIREMENTS.md` can support.

## Deletion and conformance gate

- No ROADMAP status is hand-asserted without a `delivers` field.
- `check-delivery-status.sh` is the single owner of the row↔requirement correlation; the
  `Done`-vs-🔵 check inside `check-documentation-authority.sh` is deleted and its case absorbed
  here, so one script owns the relationship.
- Every plan in `docs/plans/` carries `Delivers:`.
