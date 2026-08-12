# COR-38 — Retire COR-33 stage-1 dry-run and make CRLF encoder per-line

- **Status:** Approved; not implemented
- **Delivers:** REQ-113
- **Driver:** Address warm debt from COR-33 while context is fresh. Stage-1 honesty (`canPerformCodeBlock` dry-run with dummy `ID=0`) re-proves via `SemanticEditEngine.plan` what stage-2 atomic now guarantees; stage-2 encoder expands `\n→\r\n` uniformly, not per-line, so a mixed `LF`/`CRLF` fenced block would over-expand the edited line.

## Scope

Two tightly coupled cleanups of the same concern — CRLF code-block fidelity — that are correct only together after stage 2:

1. **Retire the stage-1 dry-run.** `EditorCommandController.availability(for: .codeBlock)` branches to `session.canPerformCodeBlock(at:)` which builds a full `EditorEditRequest` and runs `SemanticEditEngine.plan` with `nextSnapshotID = ID(0)`. After `.normalizedCodeBlock` exists, CRLF code content is no longer `.uneditable`, so availability should predicate on the projection's own classification at the target or collapse to the `default` branch. Keep the current refusal shape for genuinely `.uneditable` content (e.g. raw HTML at the caret) — the plan's fallback 3 — but without re-running the engine.

2. **Make `MarkdownLiteralEncoder.encode(decoded:kind:)` per-line.** Currently `decoded.replacingOccurrences(of:"\n", with:"\r\n")` uniformly. Uniform CRLF files are proven preserved (`CRLFCodeBlockTests.editingOneLinePreservesOtherTerminators`, `lfDocumentUnchanged`). Mixed line endings (`line1 LF`, `line2 CRLF`) would turn line1 into `CRLF` after editing line2. Carry source line terminator per atomic.

## Requirements and invariants

- REQ-007 — edited line's untouched siblings stay byte-identical, including per-line terminator.
- REQ-113 — `enabled` implies `performable`; stage-1 debt is the current `enabled`-via-dry-run shape that must be replaced without regressing `enabled` semantics.
- REQ-088 — Swift 6 concurrency clean.
- ARC-007/009 — coordinate exact-or-refuse unchanged; this refines case 2 (`atomic` with proven decoder/encoder), not a new case.
- ARC-018 — typography/presentation unchanged.
- **Architecture impact:** none beyond approved `ENGINEERING §6` case 2. No new `ARC-###`. `ENGINEERING §6` wording already says per-line; no spec change.

## Alternatives considered and rejected

- **Keep dry-run permanently.** Honest but heavier: availability is per-keystroke/toolbar refresh, and it duplicates the planner's post-mutation authoritative check already covered by `ProjectionAtom`. Rejected as tech-debt retention.
- **Keep uniform encoder.** Honest for uniform files per `REQ-007` (untouched bytes), but `REQ-007` is per-line for the edited line's own terminator shape; mixed files are real on Windows. Rejected.
- **Store document-level `lineEnding` enum and branch.** Simpler but loses per-line fidelity for mixed files; same rejection as uniform.

## Production route

Modify:

- `Markdown Editor/EditorCommandController.swift` — remove `.codeBlock` special-case; fall through to `default` which checks `isCurrentWYSIWYG`. No longer calls `session.canPerformCodeBlock`.
- `Markdown Editor/EditorCommandValidation.swift` — remove `case .uneditableContent` if no longer cited (keep if any other caller remains; this plan removes the only caller).
- `Markdown Editor/EditorSession.swift` — delete `canPerformCodeBlock(at:)` (stage-1 method). No other file calls it.
- `Markdown Editor/ProjectionAtom.swift` — extend `AtomicSourceAtom` or `normalizedCodeBlock` payload to carry per-line terminator kind (`lf` vs `crlf` vs `none` for final line without newline) as `terminator: Terminator` (`Sendable, Equatable`). `concreteAtoms` sets it from the two-byte source slice (`0x0D 0x0A` → `.crlf`, else `.lf`/`none`).
- `Markdown Editor/StructuralSourceSpans.swift` — no change (already per-line), but `ProjectionCompiler` indented-code path already filters `\r`; keep.
- `Markdown Editor/MarkdownLiteralEncoder.swift` — change `encode(decoded:kind:)` to per-line walk: split `decoded` on `\n` preserving empty segments, re-join using per-atom terminators in order; if terminator count mismatches decoded line count, fall back to uniform expansion and record `presentationRecovered` (never guess). Add `encode(decoded:atoms:)` overload used by `ProjectionCompiler` if needed; keep old `encode(decoded:kind:)` as deprecated shim calling new overload only for uniform case to avoid breaking non-code callers.
- `Markdown Editor/SemanticEditPlanners.swift` — replace the three `if body.hasSuffix("\r\n") dropLast(2) else if hasSuffix("\n") dropLast()` blocks (`toggleCodeFence`, `transformLine`, `ListEditPlanner.toggle`/`toggleBlockQuote` line = 4 sites) with single `String.crlfAwareTrimmingNewline() -> (trimmed: String, hadNewline: Bool, terminator: Terminator)` helper in `MarkdownSourceIndex.swift` or a new `String+CRLF.swift`. Same helper used for per-line encoder terminator memory.

No new production type beyond `Terminator` enum and the helper; no new `TextKit` path.

## Implementation phases

1. **Rehearse the current guard:** run `CommandLivenessMatrixTests` and `CRLFCodeBlockTests` — must be green before touching. Confirm `codeBlockStaysEnabledForLFWithUneditableHTML` proves target-covering, not document-wide any-`.uneditable`.
2. **Retire dry-run:** delete `canPerformCodeBlock`, collapse `availability` branch, delete unused `uneditableContent` case if dead. Run `CommandLivenessMatrixTests.codeBlockIsEditableInCRLFWYSIWYG` (must stay green for both CRLF and LF), `lineReshapingCommandsApplyInCRLFWYSIWYGDocuments` (includes `.codeBlock`), and the stage-1-specific `codeBlockAvailabilityIsHonestForCRLF` — which will now fail because it expects `disabled` before atomic; that expectation is retired and replaced by the `enabled+accepted` stage-2 proof. Update its anchor to `Verifies: REQ-113 (retired stage-1)`.
3. **Per-line encoder:** add `Terminator` to `AtomicSourceAtom`, wire `concreteAtoms`, implement per-line `encode`. Mixed fixture test first: `mixedLineEndingsPreserveUntouchedTerminators` — source `"```\nline LF\nline CRLF\r\n```\n"` with edit of one interior line preserves the other's terminator byte-identically. Must fail against uniform encoder, pass after.
4. **Dedup helpers:** extract `crlfAwareTrimmingNewline` and use at 4 call sites; run `MarkdownSourceIndexTests`.
5. **Reconcile** `REQUIREMENTS.md` `REQ-113` verified-by to cite only stage-2 proofs plus the new mixed test; remove stage-1 `disabled` cell note from the living doc (history in Git). `REQ-007` already cites `CRLFCodeBlockTests`; add mixed test there.
6. **Gates:** `Scripts/check-documentation-authority.sh`, `Scripts/check-instrumentation-coverage.sh`, `Scripts/check-proof-results.sh` (full suite), `Scripts/fast-check.sh`. Smoke screenshot still passes (no visual change).

## Automated non-UI proof

- `CommandLivenessMatrixTests` — closed matrix over `EditorCommand.allCases` x both modes; a new command with undeclared behavior fails. Must include CRLF doc case for `.codeBlock` now `enabled+accepted` (stage-2 already added, keep).
- `CRLFCodeBlockTests.editingOneLinePreservesOtherTerminators` — uniform CRLF preservation (kept).
- `CRLFCodeBlockTests.mixedLineEndingsPreserveUntouchedTerminators` — **new**, mixed case above — fails before, passes after.
- `CRLFCodeBlockTests.lfDocumentUnchanged` — LF byte-identical (kept).
- `CRLFCodeBlockTests.decoderRoundTrips` — per-line round-trip table (kept, extend with mixed case).
- `MarkdownLiteralEncoderTests` per-line encode table (if exists; else add to `CRLFCodeBlockTests`).
- No new smoke/screenshot proof beyond existing.

## Instrumentation and performance evidence

No new trace event. Measure `nativeInputCallback` p95 before/after — retiring dry-run should reduce availability cost (not a gate, informational). Re-record is not required; report wall-clock delta in PR.

## Failure and rollback behavior

- If per-line terminator count mismatches `decoded` line count, fall back to uniform encoder and emit `presentationRecovered` (visible over silent wrong bytes). Source never rewritten to make mapping work; `REQ-007` preserved for uniform, honest for mixed edge.
- If dry-run removal reveals a genuinely `.uneditable` target that stage-2 was supposed to cover but does not (e.g. CRLF inside inline `softBreak`), the command will report `enabled` and then `refused` — `REQ-113` violated. Roll back to dry-run and re-diagnose; do not re-introduce document-wide any-`.uneditable` check.

## Deletion and conformance gate

- No `canPerformCodeBlock` or `uneditableContent` remains if unreferenced; no second availability predicate.
- One `Terminator` source-of-truth; no duplicate line-ending sniff.
- One `crlfAwareTrimmingNewline` helper; no inlined `hasSuffix("\r\n")` at 4 sites.
- Delete this plan in the implementing change; Git retains history.
- Both gate scripts pass; proof-results gate shows `mixedLineEndingsPreserveUntouchedTerminators` executed+passed.
