# ADR-0001 — Spec-driven documentation with conservative authority

- **Status:** Accepted
- **Date:** 2026-07-21
- **Deciders:** Toni Melisma
- **Related:** [CLAUDE.md](../../CLAUDE.md), [VISION.md](../VISION.md); meta-decision for all work

## Context

This is an AI-assisted ("spec-driven") project. Spec-driven development (SDD) emerged as the
antidote to "vibe coding," where agents produce plausible code that drifts from intent. Two
philosophies exist: **radical** — the spec is the *sole* source of truth and code is
regenerated output; and **conservative** — code + tests remain canonical while specs are the
synchronized intent layer (closer to TDD). We are building a real, shippable native macOS app
whose hard edge cases (AppKit/TextKit) live in code, not prose.

## Decision

Adopt SDD with **conservative authority**: code + tests are canonical; the docs are a
synchronized intent layer kept in lock-step by an "update everything" discipline and
mechanical, grep-able traceability (`REQ-###` anchors). The doc set is MECE:
`VISION` (truths) · `REQUIREMENTS` (what) · `ROADMAP` (when) · `decisions/` (why) ·
`research/` (investigation) · `plans/` (how) · `CLAUDE.md` (process). Nothing enters the
docs without the user's explicit approval (the Prime Directive).

## Consequences

- **Positive:** intent is captured and reviewable; drift is fought by a DoD checklist +
  traceability; the docs never pretend generated code is disposable.
- **Negative / costs:** per-change discipline overhead; needs a "fast lane" so trivial changes
  aren't over-ceremonied.
- **Follow-ups:** the traceability check should become automated (pre-commit/CI) later.

## Alternatives considered

- **Radical / spec-as-source-of-truth:** rejected — awkward for a native app where TextKit /
  AppKit edge cases are inherently code, not prose.
- **No system / ad-hoc prompting:** rejected — the drift/decay problem SDD exists to solve.
