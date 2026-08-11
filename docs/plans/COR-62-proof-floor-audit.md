# COR-62 — Audit the proof floor

- **Status:** Approved; not implemented
- **Requirements:** REQ-138 (satisfied across the whole corpus); every current `Done` row is in scope
- **Delivers:** REQ-138
- **ARC invariants:** every `ARC-###` and `ARC-Q##` re-verified against its named proof
- **Executor:** **not junior work.** Answering the four questions below is the same judgement that
  COR-61 phase 2 requires, applied a hundred times. An agent that answers them optimistically
  reproduces 2026-08-10 with better paperwork — the failure mode here is a green audit, not a red
  one. Run in batches with user review of each batch's demotions, and treat a batch that demotes
  nothing as a signal to re-examine the batch, not as good news.
- **Blocked on COR-61** phases 1–3.

## Context

`REQUIREMENTS.md` holds **100 `Done` requirements, 7 `Correction`, and 6 `Planned`** as of the
documentation increment of 2026-08-10, which demoted REQ-123..128 from `Done`. Every one of those
hundred was admitted by the gates that COR-57..COR-61 replace: gates that check a proof *exists*, *is
cited*, and *passes* — and which have now been defeated in six recorded ways.

The base rate is not speculative. This repository has already caught three months-long false
positives, each under these same gates:

- **REQ-058** was `Done` for months while four of its formatting commands reported `enabled` and
  silently refused, because every cited proof asserted availability, window scoping, or refusal.
- **REQ-109** sat `Done` for months while four of its cited proofs were failing, in a suite that
  never completed. PR #29 reported *"Debug 328 passed / 0 failed"*.
- **REQ-090** was `Done` on a p95 measured over `String(repeating: "word ", count: 20_000)` — 100,000
  UTF-16 units containing no newline, heading, list or table, which cmark parses as one paragraph —
  while a sibling proof measured the same work on structured text at three times the cost.

Three false positives found by accident rather than by a gate is not evidence that the rest are
sound. It is evidence that the detection method was accident.

The user's decision, recorded 2026-08-10, is a **full audit of every `Done` row**. This increment is
expected to produce a substantial `Correction` backlog. That is its purpose, not its failure mode:
the deliverable is an honest requirements table, and an honest table carrying thirty `Correction`
rows is worth more than a dishonest one that reports every row `Done`.

## Architecture impact

None by intent. If the audit finds an `ARC-###` invariant whose named proof does not discriminate it,
that is an architecture-gate matter under `CLAUDE.md` §3 and `ENGINEERING.md` §15: stop, record the
counterexample, and return to a separate discovery unit. Do not repair an invariant inside this
increment.

## Production changes

None. This increment writes `Falsification/` entries, moves `REQUIREMENTS.md` rows, and records
findings. **It fixes nothing it finds** — every defect becomes a `Correction` row and a ROADMAP
entry. Mixing repair into the audit would make the audit's own completeness unverifiable, and would
reproduce in the large the mistake `CLAUDE.md` §3 forbids in the small.

## Phases

Requirements are audited in dependency order, hardest-consequence first, so that a finding which
invalidates a whole class surfaces early:

1. **Architecture-bearing rows** — every requirement cited by an `ARC-###` or `ARC-Q##`.
2. **Liveness-bearing rows** — every requirement promising a user-invocable capability. `CLAUDE.md`
   §4's liveness rule was added because of REQ-058; this phase verifies it actually took.
3. **Measurement rows** — every requirement quantifying over a class of inputs. REQ-090's corpus
   defect is the template; the question for each is whether the proof enumerates the class or picks
   a representative.
4. **The remainder.**

Per requirement, the audit asks exactly four questions and records the answers:

| Question | Failing answer means |
| --- | --- |
| Does a valid `Falsification/` entry exist — a plausible defect that turns a cited proof red? | The proof does not discriminate. → `Correction` |
| Do the cited proofs assert the thing the requirement is *about*? | REQ-106's defect: model values asserted where rendered geometry was promised. → `Correction` |
| If the requirement quantifies, do the proofs enumerate the class structurally? | REQ-090's defect. → `Correction` |
| If the requirement promises a capability, does a proof show it *succeeding*? | REQ-058's defect. → `Correction` |

## Automated proof

The audit's completeness is itself gated, not asserted:

- `Scripts/check-falsification.sh --all` passes, which by REQ-138 requires a valid entry for every
  row still marked `Done` — so a row cannot survive the audit by being skipped;
- the count of `Done` rows plus `Correction` rows equals the pre-audit row count, proving no row was
  quietly deleted rather than demoted;
- `Scripts/check-delivery-status.sh` passes, so every ROADMAP ✅ still resolves to rows that remain
  `Done` after the audit — a demotion that falsifies a delivered increment forces that increment's
  row back to 🔵, which is the honest outcome and must not be edited around;
- a written audit record, one line per requirement with its four answers, committed under
  `docs/research/` with evidence-only authority so a later refresh can tell what was checked and
  when.

## Instrumentation and performance evidence

None. The audit consumes `--all`, whose cost COR-61 records as 1.5–3.5 hours per sweep. Budget for
several sweeps as entries are authored.

## Failure and rollback

- **Scale.** If phase 1 shows a false-positive rate above roughly a third, stop and re-plan with the
  user before continuing: at that rate the correct response is not a longer audit but a re-examination
  of how requirements are admitted in the first place, which is a discovery unit, not this one.
- **Demotion cascades.** Demoting a requirement can falsify a delivered increment and reopen a
  ROADMAP row. Follow it; do not stop the cascade to protect a ✅.
- **Scope creep into repair.** The strongest pressure in this increment will be to fix a defect while
  it is in front of you. Do not. Record it and move on.

There is no rollback: the audit records findings and the findings are true. Reverting it would
restore claims already known to be false.

## Deletion and conformance gate

- Every requirement that was `Done` before the audit is now either `Done` with a valid
  `Falsification/` entry, or `Correction` with a named increment expected to clear it.
- No requirement row was deleted.
- Every `ARC-###` and `ARC-Q##` names a proof that survived question 1.
- The audit record is committed and indexed in `docs/research/README.md`.
