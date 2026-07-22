# ADR-0005 — Discovery and build are separate units

- **Status:** Accepted
- **Date:** 2026-07-21
- **Deciders:** Toni Melisma
- **Related:** [CLAUDE.md §3](../../CLAUDE.md); [ROADMAP.md](../ROADMAP.md) (SPIKE-01)

## Context

The increment lifecycle spans research → clarify → specify → plan → implement. Bundling
production coding together with research, spikes, discovery, or requirements-setting blurs
what is being reviewed and approved, and lets un-vetted decisions leak into code. A spike in
particular produces throwaable exploration, not shippable code.

## Decision

**Discovery and build never mix in one unit.** Research, spikes, discovery, requirements-
setting, and planning are completed and approved as their own unit(s) — **with no production
code** — before any implementation. **Spikes are standalone** (their POC code is throwaway,
not merged). A build unit implements an already-approved plan and does not define new
requirements or decisions. Reconciling requirement *status* and traceability *after* coding is
part of the build unit; *setting* requirements is discovery. The text-engine investigation is
carried as standalone **SPIKE-01** between INC-01 and INC-02.

## Consequences

- **Positive:** clean, reviewable units; decisions are vetted before code depends on them;
  throwaway spike code never pollutes `main`.
- **Negative / costs:** more, smaller units and hand-offs; a little more process overhead.
- **Follow-ups:** none beyond keeping ROADMAP unit types honest (`[docs]` / `[discovery/spike]`
  / `[build]`).

## Alternatives considered

- **One increment does research + code:** rejected — the mixing this ADR exists to prevent.
