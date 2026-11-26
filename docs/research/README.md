# Research

Research preserves expensive, still-valid evidence: standards analysis, platform investigation,
benchmarks, and throwaway POC results. It is **evidence, not architecture or authorization**.
Current product truth is in `../VISION.md`; current architecture is in `../ENGINEERING.md`.

A research document remains only while its facts are useful and its assumptions still hold. It
must state:

- evidence authority;
- first-researched and last-verified dates;
- environment and pinned revisions where relevant;
- reproducible method;
- findings separated from recommendations; and
- explicit refresh triggers.

When a dependency, SDK, requirement, or architectural assumption invalidates material findings,
the document is refreshed in full or deleted. Warning banners do not make stale facts acceptable.

Current evidence:

- [2026-11-26-cloud-first-development.md](2026-11-26-cloud-first-development.md): cloud
  sessions, GitHub's macOS runners, CLAUDE.md guidance, Sparkle releases, and what latchkey and
  Otos do. Refresh when Sparkle, the `xcode-27` image or the cloud environment changes, or when
  the repository's visibility does.

- [Architecture specification practices](architecture-specification-practices.md)
- [macOS editor platform](macos-editor-platform.md)
- [Markdown projection and compatibility](markdown-projection-and-compatibility.md)
- [Image portability and safety](image-portability-and-safety.md)
- [Native Markdown typography](native-markdown-typography.md)
- [DISC-01 — Semantic selection anchor vs scoped ARC-009](DISC-01-semantic-selection-anchor.md)
- [DISC-08 — Does AppKit's Dynamic Type route reach this app's editor content?](DISC-08-macos-text-scaling.md)
- [COR-71 — Stage 0 local-transition probe](COR-71-stage0-local-transition-probe.md)
- [COR-71 — Release performance evidence](COR-71-release-performance.md)
- [Performance baseline](performance-baseline.md)
- [COR-80 — Incremental/full lexer parity divergences](COR-80-incremental-lexer-parity.md)
- [COR-81 — WCAG contrast conformance of the approved appearance](COR-81-contrast-conformance.md)
- [COR-83 — Stage 0 process leak tooling decision](COR-83-leak-tooling.md)
