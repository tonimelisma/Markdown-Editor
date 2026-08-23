# Plans

This directory contains approved, unimplemented production plans. Several may coexist. A plan is
deleted when its work merges — **as tidying, never as evidence**. Delivery evidence is one thing
only: observed gate output, quoted. See `../DECISIONS.md` for why that distinction is load-bearing.

Plans implement the current architecture in `../ENGINEERING.md`. They do not redefine it.

## What a plan must answer

Four questions. **Write only what the increment actually has** — a plan for a one-line build-setting
change has no rollback behavior, and inventing a section for it produces ceremony, not thought.

1. **What is broken, and what is the evidence?** A reproduced defect, a measurement, or a
   requirement with no proof. Not "we should".
2. **What is the smallest change that fixes the cause rather than the symptom?** Name the files,
   types, and routes — including what gets **deleted**, since this repo keeps no displaced paths.
3. **What proof turns red if this is wrong?** `CLAUDE.md` §3's question, asked once, in the plan.
4. **What decisions does this make, and on what criteria?** Blockers, architecture changes,
   product judgement. Decide them by `CLAUDE.md` §7's method — criteria, alternatives, ranking,
   choice — and record the ones with consequences in `docs/DECISIONS.md`. Do not hand a decision
   back as a question. This is also the **Executor** line: who may implement it and what judgement
   it demands.

Add anything else the increment genuinely has — ordered phases, instrumentation, failure behavior,
a deletion gate — when it has one. Nothing here is a required heading, and no gate enforces this
format. A format enforced by a gate is a format that gets satisfied by an artifact.

## Executing a plan

Read `../../CLAUDE.md` first. Then:

1. **Check the Executor line and the blockers.** Some plans are blocked on another increment; some
   demand judgement, which the executor supplies by `CLAUDE.md` §7's method rather than by asking.
2. **Take them in ROADMAP order.** The order encodes real dependencies. After its named blockers
   land, a plan must be implementable and mergeable without bundling another plan.
3. **Work in a worktree on a branch** (`inc-NN-slug` / `cor-NN-slug`), never on `main`. Swift
   changes need a PR and a separate-agent review; docs and project config commit directly to `main`.
4. **Run the gate and read its output.** `Scripts/check.sh`. A plan is not done because its steps
   were performed — it is done when its stated proof is observed passing.
5. **If the plan is wrong, stop.** A plan that does not survive contact with the code is a finding.
   Say so and re-plan; do not improvise production changes the plan does not authorise, and do not
   commit a placeholder to keep the sequence moving. On 2026-08-10 ten increments were committed as
   one-line stubs rather than reported as not-started, and the ROADMAP recorded them as delivered.
6. **Characterize before replacing.** Existing production behavior may already satisfy part of a
   plan. Keep proven correct code, add missing route evidence, and replace only a reproduced defect.

### `file.swift:NNN` references are indicative; symbols are authoritative

Plans cite line numbers to make a construct findable. Line numbers drift. If a citation no longer
lands on what its surrounding prose describes, trust the description and the symbol name, and fix
the citation in the same change.
