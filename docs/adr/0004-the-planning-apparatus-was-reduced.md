# 0004. The planning apparatus was reduced

- Status: accepted
- Date: 2026-08-22

## Context and problem

**The evidence was self-inflicted, which is why it counts.** COR-86 — a change that sets one build
flag, adds one enum case, and adds one test — was written to the thirteen-section specification
and came out at ~150 lines, including an *Instrumentation and performance evidence* section and a
*Failure and rollback behavior* section for a change that has neither. The sections were filled
because they were required. That is the dynamic [ADR 0001](0001-the-verification-apparatus-was-removed.md) diagnoses, in a document written
an hour after reading it: **thirteen mandatory headings are thirteen proxies for thinking, and the
cheapest way to satisfy a mandatory proxy is to produce the artifact it measures.**

**The deletion signal had already been defeated once.** Making plan deletion the delivery signal
is what allowed ten increments on 2026-08-10 to be marked delivered by deleting their plans,
having built one comment line each. The response at the time was a warning sentence in
`CLAUDE.md` §5 — *"A plan's absence proves nothing"* — rather than removing the signal. A proxy
that has been gamed once and is retained with a note asking people not to game it is a proxy
waiting to be gamed again. Delivery evidence is now one thing: observed gate output, quoted.

**Why `Implemented in` went.** 112 rows naming production types, hand-maintained, with nothing
checking them. That is the manifest `find` field with a different name, and [ADR 0001](0001-the-verification-apparatus-was-removed.md)
records exactly how those ended: *"a hand-maintained second copy of the code with nothing checking
them, and every refactor rotted them silently."* `Verified by` stays, because a reader looking for
a proof benefits from a test name, and the code-side `// Verifies: REQ-###` comments make the
mapping recoverable when it drifts. One direction, owned by the code.

**What was kept, and why.** The honesty rules (`CLAUDE.md` §3) — judgement, not machinery. One
gate, unchanged. The no-UI-tests rule and its two passive exceptions. Closed-set discipline: every
finding in the 2026-08-22 review lives in a *gap between* closed sets, never inside one. Consent
(§7) and the architecture-change bar (§6), both cheap and both load-bearing. Plans stay in-repo
rather than moving to PR descriptions, because the agents that do most of the work here read the
repository and not the GitHub API.

**No gate enforces the new plan format.** A format enforced by a gate is a format that will be
satisfied by an artifact. That is the whole argument, and it applies to this change too.

## Decision drivers

- Mandatory headings are proxies for thinking, and the cheapest way to satisfy one is the artifact it measures.
- A signal that was gamed once will be gamed again.

## Considered options

### Thirteen mandatory plan sections, plan deletion as delivery signal

- Bad: a three-line change produced a 150-line plan; ten increments were marked delivered by deleting their plans.

### Four advisory questions, delivery shown by observed gate output (chosen)

- Good: plans say what the increment actually has.

## Decision

**Decision.** `docs/plans/README.md`'s thirteen mandatory plan sections became four questions,
explicitly advisory. Plan deletion stopped being a delivery signal. `docs/roadmap.md` lost its
COR-18 – COR-85 delivery ledger (317 lines → ~100). `docs/requirements.md` lost its
`Implemented in` column. `CLAUDE.md` §3 gained two rules.

## Consequences

As stated above.

## Confirmation

Delivery evidence is the gate's quoted output in the PR's final report. Plans now live in GitHub issues and PR descriptions (the four questions are kept in `docs/development.md`).

## Retirement proof

Evidence that increments ship without the thinking the questions ask for.

## Reversal plan

Reinstate required sections in the PR template; `script/pr-check` already enforces its headings.
