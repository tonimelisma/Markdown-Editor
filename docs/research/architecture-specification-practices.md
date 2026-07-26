# Architecture specification practices

- **Authority:** Evidence only; `../ENGINEERING.md` and `../CLAUDE.md` are authoritative.
- **First researched:** 2026-07-25
- **Last verified:** 2026-07-25
- **Method:** Compared ISO architecture-description concepts, arc42's pragmatic structure, SEI
  quality-scenario guidance, evolutionary architecture fitness functions, and the repository's
  repeated correction history
- **Refresh when:** documentation authority, architecture-change process, quality model, or
  repository scale changes

## Question

What is the minimum documentation system that makes the current architecture understandable and
enforceable without creating a stale parallel archive?

## External findings

### Describe concerns through explicit views

ISO/IEC/IEEE 42010 distinguishes the architecture itself from its description and organizes an
architecture description around stakeholder concerns, viewpoints, and model kinds. The useful
lesson for this repository is not to adopt a formal notation; it is to ensure that different
questions have explicit, consistent views.

The views needed here are:

- product drivers;
- system/component topology;
- state ownership and authority;
- runtime/edit sequences;
- concurrency and failure rules;
- quality scenarios;
- risks; and
- terminology.

Source:
[ISO/IEC/IEEE 42010:2022](https://www.iso.org/standard/74393.html).

### Keep the architecture description lean but complete

arc42 covers goals/constraints, context, strategy, building blocks, runtime behavior,
cross-cutting concepts, quality requirements, risks, and glossary. It explicitly supports a lean
application of the structure and recommends avoiding redundant requirement text.

For this small application, those concerns fit in one current `ENGINEERING.md`. Splitting them
among numerous component specifications would increase synchronization cost without creating a
new authority boundary.

Sources:

- [arc42 overview](https://arc42.org/overview)
- [arc42 documentation](https://docs.arc42.org/home/)
- [arc42 introduction and quality goals](https://docs.arc42.org/section-1/)

### Use measurable quality scenarios

SEI guidance treats performance, reliability, modifiability, usability, and other qualities as
architectural drivers. A quality label alone is ambiguous; a concrete scenario identifies the
stimulus, environment, response, and measurable response.

For an editor, “responsive” is weaker than:

> Given a current 100,000-unit document, 100 consecutive accepted insertions appear exactly once
> and in order while translation p95 remains below 8 ms.

Scenarios expose trade-offs and make architectural evaluation repeatable.

Sources:

- [SEI quality attributes](https://www.sei.cmu.edu/library/quality-attributes/)
- [SEI reasoning about software quality attributes](https://www.sei.cmu.edu/library/reasoning-about-software-quality-attributes/)
- [SEI scenario-based architecture analysis](https://insights.sei.cmu.edu/library/scenario-based-analysis-of-software-architecture/)

### Make invariants executable

Evolutionary architecture uses fitness functions to continuously measure whether a system still
satisfies its intended characteristics. For this repository, fitness functions include compiler
types, reducer/oracle tests, generated fixtures, source-conformance checks, privacy-safe traces,
and Release benchmarks.

A prose invariant without a discriminating proof is easy to reinterpret during a correction. A
test without a named invariant can remain green while the architecture changes around it. The
matrix between `ARC-###` invariants and proofs is therefore the important mechanism.

Source:
[Building Evolutionary Architectures, second-edition sample](https://www.thoughtworks.com/content/dam/thoughtworks/documents/books/bk_building_evolutionary_architectures_second_edition_free_chapter.pdf).

## Repository findings

The former documentation set recorded many individual decisions and completed plans, but did not
provide one present-tense model for:

- sole state owners;
- canonical versus derived versus transient state;
- allowed mutation direction;
- synchronous versus asynchronous edit responsibilities;
- revision identity;
- failure/refusal policy; or
- proof required to change those rules.

That gap allowed locally reasonable corrections to alternate between view-owned, document-owned,
session-owned, and duplicated state. Detailed obsolete plans and decision records remained easier
to find than the current whole-system contract.

## Current design conclusion

The minimum coherent system is:

- VISION for product direction;
- ENGINEERING for present architecture and invariants;
- REQUIREMENTS for behavior;
- ROADMAP for current sequence;
- evergreen research for still-valid evidence;
- approved unimplemented plans for code execution;
- executable conformance checks; and
- Git for history.

Separate decision records add no unique authority in this model. Implemented plans and obsolete
guidance are deleted from the working tree. Evergreen research remains only while its evidence is
current and explicitly non-authoritative.
