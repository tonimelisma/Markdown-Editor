# 0001. The verification apparatus was removed

- Status: accepted
- Date: 2026-08-22

## Context and problem

**The apparatus worked.** This is the part that matters and the part that will be forgotten.
Before removing it, the full corpus was executed for the first time: **100 of 100 recorded
mutations turned their cited proof red.** The 528-test suite passed. There were no tautological
proofs anywhere in the repository. The system was not removed because it was fraudulent. It was
removed because of what it cost.

**The cost.** At the point of removal the repository held 22,883 lines of production Swift and
21,546 lines of verification and process — 14,103 lines of tests, 4,652 lines of gate scripts
(nine of which existed only to test other gates), 898 lines of hand-written mutation manifests,
and 178 KB of specification that the manual required reading before planning. One increment cost
roughly four hours, of which the gate alone was seven minutes for the release check plus
seventeen minutes for the falsification run — a hundred incremental rebuilds. Seven increments
took about forty hours.

**Why it grew.** Read the history as a sequence. Each time a gate was defeated, the response was
"replace the question it asks", and in practice that added a layer:

> source text exists → the code executes → a *mutation* turns a proof red → a *fixture* rehearses
> the gate failing → a *rule* requires that rehearsal be recorded

Every step was a correct local response to a real failure. The sum was a system in which proving
a change cost more than making it.

**Why it had started manufacturing its own defects.** The last rule added — every `Done`
requirement carries a compiling mutation of production source that turns a cited proof red —
was satisfied, in the final in-flight increment, by writing production code that exists in order
to be mutated. `EditorInputRoute.contract` was a hundred-line table mapping each callback route
to an owner and a state transition. No production code read it. One test restated the same table
and compared. Two manifests recorded their falsifying mutations against it, and both passed the
gate while proving nothing about the running application. That table and its mirror test were
deleted along with the apparatus.

This is Goodhart's law with a fast feedback loop. Each gate makes one proxy for "real proof"
mandatory; the cheapest way to satisfy a mandatory proxy is to build the artifact it measures.
A stricter gate raises the price of faking it without changing the incentive.

**A second, independent flaw.** A manifest's `find` field was an exact string match against
production source. The 81 manifests were therefore a hand-maintained second copy of the code
with nothing checking them, and every refactor rotted them silently. This happened: COR-72 added
a second `return result` to `MarkdownHighlighter.swift`, which made REQ-051's mutation ambiguous.
Nobody noticed, because the release gate ran falsification as `--changed
$(git merge-base origin/main HEAD)..HEAD`, and on `main` that range is empty. The gate reported
`PASS` over zero manifests for every merge to `main` for months.

**What was kept, and why.**

- **All 528 tests.** They are the real asset and none were removed.
- **The smoke test.** Launching the built app on a fixture and reading its structured log is
  cheap, fast, and catches the class of failure unit tests structurally cannot.
- **The screenshot verifier.** One passive window capture, for human eyes.
- **The honesty rules**, now `CLAUDE.md` §3. They are judgement, not machinery. The single most
  valuable one — *what change to production code makes this test go red?* — is exactly the
  question the falsification system automated. Asking it costs nothing. Automating it cost
  17 minutes a run and eventually produced code written to answer it.

## Decision drivers

- The cost of proving a change against the cost of making it.
- Whether a gate can be satisfied by an artifact instead of by the behavior it is about.

## Considered options

### Keep the verification apparatus

- Good: 100 of 100 recorded mutations turned their cited proof red.
- Bad: about as many lines of process as of product, roughly four hours per increment, and production code written to be mutated.
- Failure modes: manifests rot silently against refactors; a gate passes over zero manifests.

### One gate that builds, tests and smokes (chosen)

- Good: the tests stay; the cost falls to one script.
- Bad: nothing mechanical asks "what change makes this test go red"; the honesty rules in CLAUDE.md ask it instead.

## Decision

**Decision.** The falsification-manifest system, the proof-results gate, the delivery-status
gate, the instrumentation-coverage gate, the documentation-authority gate, the measurement-
provenance gate, the push-policy gate and its Git hook, and the nine fixture scripts that tested
those gates were all deleted. `Scripts/fast-check.sh` and `Scripts/full-check.sh` were replaced
by one `Scripts/check.sh` that builds, tests, and smokes.

## Consequences

As stated above.

## Confirmation

`Scripts/check.sh` is the one gate, and CI's `CI gate` the one required check. A new gate is reviewed against "If you are about to add a gate" below. The traceability check added later (`script/process-check`) asks only whether IDs and tags agree, not for an artifact per proof.

## Retirement proof

**If you are about to add a gate.** The question is not "would this catch a real defect?" — the
answer is almost always yes. The question is "what will someone write to satisfy this cheaply,
and is that thing worse than the defect?" If a gate can be satisfied by an artifact rather than
by the behavior it is about, it will eventually be satisfied that way, by someone under time
pressure who is not being dishonest.

## Reversal plan

The apparatus is in Git history before this change; restoring it costs the four-hour increments it cost before.
