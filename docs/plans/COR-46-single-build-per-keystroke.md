# COR-46 — One document build per keystroke

- **Status:** Approved; not implemented
- **Requirements:** REQ-090 (stays `Correction`; COR-48 clears it), REQ-109, REQ-123
- **ARC invariants:** ARC-005/007/009/019 unchanged. No architecture change — this removes redundant work only.

## Context

For one inserted character, `SemanticEditEngine.plan` can call
`AuthoritativePresentationBuilder.build` — a complete cmark parse under a process-wide mutex, plus a
complete source index, plus a complete projection compile — from three places:

1. `WYSIWYGPlanningDomain.literalCandidatePreservesPresentation` (`WYSIWYGPlanningDomain.swift:411`),
   for every non-empty `insertText`;
2. `WYSIWYGPlanningDomain.contextualLiteralMutation` (`:512`), which calls it again per candidate;
3. `SemanticEditEngine.planAuthoritativeTransition` (`SemanticEditEngine.swift:303`), which discards
   the snapshot the first two just built and builds it again.

`ProjectionOracle.validate(snapshot:)` then runs a further whole-document pass, sometimes twice on the
same immutable snapshot.

Every one of these produces the same result for the same
`(source, revision, snapshotID, locationGeneration)` tuple. The redundancy is pure waste with no
semantic content, and removing it needs no research, no architecture change, and no new invariant.

Expected effect: a 2–4× reduction in the dominant cost of an inserted character. This does not fix
the underlying design — COR-48 does that — but it is bankable immediately and it makes COR-48's
measurements interpretable.

## Production changes

### 1. `Markdown Editor/WYSIWYGPlanningDomain.swift` — return the work instead of discarding it

Replace `literalCandidatePreservesPresentation(...) -> Bool` with:

```swift
/// Result of proving whether an encoded literal insertion leaves semantic structure unchanged.
///
/// Carries the snapshot that was built to decide it. The previous `Bool` threw that snapshot away
/// and every caller rebuilt the identical source.
nonisolated enum LiteralCandidateProof: Sendable {
    case preservesPresentation(built: PresentationSnapshot)
    case changesPresentation(built: PresentationSnapshot)
    case unbuildable
}

static func literalCandidateProof(
    mutation: SourceMutation,
    snapshot: SourceSnapshot,
    presentation: PresentationSnapshot,
    projectionRange: NSRange,
    visibleReplacement: String,
    nextSnapshotID: PresentationSnapshot.ID
) -> LiteralCandidateProof
```

The `Bool`-returning function is **deleted in this change** — no wrapper, no deprecated alias
(`ENGINEERING.md` §15: no compatibility layers).

`contextualLiteralMutation` returns `(mutation: SourceMutation, built: PresentationSnapshot)?` and
threads the snapshot from the candidate that succeeded.

### 2. `Markdown Editor/SemanticEditEngine.swift` — accept a pre-built snapshot

```swift
static func planAuthoritativeTransition(
    mutation: SourceMutation,
    snapshot: SourceSnapshot,
    presentation: PresentationSnapshot,
    nextSnapshotID: PresentationSnapshot.ID,
    affinity: SelectionAffinity,
    taskNodeID: MarkdownNodeID? = nil,
    projectionSelectionLocation: Int? = nil,
    prebuilt: PresentationSnapshot? = nil
) -> EditorEditOutcome
```

Reuse is **guarded, never trusted** — a prebuilt snapshot is usable only when it is demonstrably for
this mutation:

```swift
if let prebuilt,
   prebuilt.id == nextSnapshotID,
   prebuilt.sourceRevision.value == nextRevision,
   prebuilt.locationGeneration == presentation.locationGeneration,
   prebuilt.sourceUTF16Count == (usableSource as NSString).length {
    nextFixed = prebuilt
} else {
    guard let built = AuthoritativePresentationBuilder.build(...) else { return .refused(.unprovable) }
    nextFixed = built
}
```

An identity mismatch falls back to building rather than refusing: the caller's contract is unchanged,
and a silently wrong snapshot is the one outcome this must not produce.

### 3. `Markdown Editor/PresentationSnapshot.swift` — memoise the oracle

```swift
/// Oracle result memoised per snapshot identity.
///
/// A snapshot is immutable, so validating it twice can only return the same answer at twice the
/// cost — and validation is a whole-document pass.
private let oracleResult: ProjectionOracle.Result
var isOracleValid: Bool { ... }
```

Populated once in `PresentationSnapshot.from`. Every
`if case .failure = ProjectionOracle.validate(snapshot: x)` becomes `if !x.isOracleValid`.
`ProjectionOracle.validate(model:)` is untouched — it runs before a snapshot exists and is a
different check.

### 4. Fix the readability defects in the touched region

While in this code (`ENGINEERING.md` "no stale documents" applies to code comments too):

- `SemanticEditEngine.swift:322–343` — reindent the `switch` sitting inside the `else` branch.
- `SemanticEditEngine.swift:447–450` — delete the empty `// MARK: - Source mode` section left by
  COR-43's split.
- `EditorSession.swift:397` — repair the duplicated doc-comment fragment
  (`/// Primary edit entry    /// Primary edit entry —`).

## Proof

The gate is COR-45's ledger matrix, which must move from failing to passing:

- `acceptedEditPerformsBoundedWork` (parameterised over `PerformanceCorpus.allCases`) —
  `documentParses <= 1` and `oracleValidations <= 1` for an ordinary insertion, for the
  `contextualLiteralMutation` route, and for the table-cell route. **Rehearsed failing** by reverting
  `prebuilt:`, which must report 2 or 3.
- `oracleValidatesEachSnapshotOnce` — a snapshot validated through two call sites performs one
  validation.
- `prebuiltSnapshotWithMismatchedIdentityIsRebuiltNotReused` — construct a `prebuilt` whose
  `sourceRevision` disagrees; assert a fresh build occurs and the outcome is unchanged. This is the
  proof that the optimisation cannot introduce a wrong snapshot.
- Existing `AcceptedEditTransactionTests`, `CommandLivenessMatrixTests`, `CRLFCodeBlockTests` and
  `PerformanceBoundaryTests` remain green — behaviour is unchanged by construction.

## Instrumentation and performance evidence

Re-record `docs/research/performance-baseline.md` and quote the delta against COR-45's baseline for
every corpus shape. The expectation to state explicitly in the PR: **the gates still fail** on
structured corpora, by a smaller margin. An increment that made them pass would mean the measurement
was wrong, not that the problem was solved.

## Failure / rollback

Pure de-duplication with identical observable behaviour. If any planner, liveness, CRLF or transaction
test fails, revert the single commit. No file format, diagnostic schema, or user-visible behaviour
changes. The guarded-reuse condition is deliberately conservative: any doubt rebuilds.

## Deletion / conformance gate

- `literalCandidatePreservesPresentation(...) -> Bool` no longer exists anywhere in the tree.
- No call site constructs a `PresentationSnapshot` for a source another call site in the same edit has
  already built — proved by `acceptedEditPerformsBoundedWork`'s `documentParses <= 1`.
- `Scripts/check-documentation-authority.sh`, `Scripts/check-instrumentation-coverage.sh` and
  `Scripts/check-proof-results.sh` pass.
