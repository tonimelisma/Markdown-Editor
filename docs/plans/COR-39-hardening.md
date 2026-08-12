# COR-39 — Helpers and typed block-container predicate

- **Status:** Approved; not implemented
- **Delivers:** REQ-118
- **Driver:** Small structural debt that is now load-bearing and cheap to fix while the surrounding code is warm.

## Scope

Three independent, zero-behavior-change hardenings that each remove a weak heuristic that could fail silently when the third `NSTextBlock` kind appears or when cmark line/column reporting changes:

1. **`MarkdownSourceIndex` inclusive→exclusive duplication.** `utf8Offset(line:column:)` returns inclusive `lineStart-1` for `column==0` and `lineStart+(column-1)` otherwise; `utf8Range` does `e+1` to exclusive. The `+1` is shared implicitly at two call sites. Make it one named conversion.
2. **`AttributedPresentationBuilder` quote-vs-code discriminator.** `style.textBlocks.filter { $0.backgroundColor == nil }.count` encodes kind via color. A third container (e.g. future callout) would collide. Replace with a typed predicate.
3. **`check-proof-results.sh` `EXEMPT` locality.** `EXEMPT` set lives only in the script (`noUITestTargetInProject`, `productionForcesNoTextKitLayout`, `productionTestHooksAreInventoried`). Exemptions are product decisions, not script decisions, and `REQUIREMENTS.md` has no record of them. Move the declaration to `REQUIREMENTS.md` (or `AGENTS.md`) and have the script read it, so documentation-authority can compose.

`SemanticEditPlanners` `hasSuffix("\r\n")` dedup is covered by COR-38's `crlfAwareTrimmingNewline` helper; this plan does not duplicate that work — if COR-38 has already landed, that helper is reused.

## Requirements and invariants

- REQ-054/055/087 — source-index exact-or-refuse; no clamp/guess.
- REQ-107 — block container geometry; no visual change.
- REQ-117/118 — proof mapping; exemptions must be traceable.
- ARC-007 — coordinates never guessed.
- **Architecture impact:** none. No new `ARC-###`; no `ENGINEERING` change beyond inline comment clarity.

## Alternatives considered

- **Leave color predicate.** Small and proven, but fails closed on next container kind — hardening now is cheaper than debugging later. Rejected.
- **Keep `EXEMPT` in script.** Tolerable, but violates "specs are current truth" — the fact that a test is exempt because it guards an absence belongs in the spec layer, not the gate layer. Rejected.
- **Add a fourth `TextBlockKind` raw value now.** Premature; only two kinds exist. Typed predicate via existing `backgroundColor` plus a dedicated test seam is sufficient.

## Production route

Modify:

- `Markdown Editor/MarkdownSourceIndex.swift` — introduce `private func exclusiveEnd(fromInclusive lastByte: Int) -> Int` or `inclusiveLastByte`→`exclusiveEnd` helper; `utf8Offset(line:column:)` for `column==0` returns inclusive last byte via helper, `utf8Range(for:)` uses the same helper for `e+1`. No caller changes. Add `// - MARK:` comment referencing `ARC-007` inclusive→exclusive contract.

- `Markdown Editor/AttributedPresentationBuilder.swift` — add a private `enum TextBlockIdentity { case quote, codeBlock }` or a `fileprivate extension NSTextBlock { var identity: Identity }` that reads `backgroundColor` plus `borderColor`/`value` once, centrally. Replace the `filter { $0.backgroundColor == nil }` site (COR-37) and the `codeBlockInsideQuote` control site with `identity == .quote`. `typography.quoteBlock()` and `typography.codeBlock()` set `backgroundColor`/border so the predicate is total by construction; add `assert` in debug that an unknown block warns via `presentationRecovered` path rather than mis-counting.

- `docs/REQUIREMENTS.md` — add an explicit `Exemptions` note under `Conventions` (or reuse `traceability` row) listing the three absence-gate tests and why each cannot be cited by a requirement (no UI test target clause, no layout-forcing clause, test-hook inventory clause). Current `Verified-by` `inherent` already covers some, but these three are `test`-kind exemptions from `REQ-118`.

- `Scripts/check-proof-results.sh` — read exemptions from the declared source instead of a hard-coded `EXEMPT` set: parse `docs/REQUIREMENTS.md` `Exemptions` table or `CLAUDE.md` `Exempt tests` list; if absent, fail closed (do not fall back to hard-coded). Pin the parse with a rehearsal.

No new test file; no new `AGENTS.md` rule beyond the exemption note.

## Implementation phases

1. **Rehearse before touching:** record current `MarkdownSourceIndexTests`, `TypographyLayoutTests.codeInsideQuoteComposesBothContainers`, `nestedBlockQuotesComposeTheirRules`, and `check-proof-results.sh --help` output.
2. **Source-index helper:** extract, keep `column==0` mapping `lineStart-1` inclusive → exclusive via helper; add `MarkdownSourceIndexTests.inclusiveToExclusiveIsSingleHelper` if cheap, else keep existing branch coverage — the point is no second `+1`.
3. **Typed predicate:** introduce identity helper, replace filter site and control assertion site; run `ParagraphGeometryTests` and `TypographyLayoutTests` at narrow/default/wide (ARC-Q15) — must stay green with same `lineFragmentUsedRect` assertions.
4. **Exemptions:** move declaration to `docs/REQUIREMENTS.md`, make script read it, rehearse script failing on an `EXEMPT` test whose declaration is removed (must fail), and passing when present.
5. **Gates:** `check-documentation-authority.sh`, `check-instrumentation-coverage.sh`, `check-proof-results.sh` (full), `fast-check.sh`. No smoke change (visual identical); run `smoke-rich.md` smoke anyway.

## Automated non-UI proof

- Existing `MarkdownSourceIndexTests` (branch for `end_column == 0`) must still branch-cover; add `utf8OffsetColumnZeroIsInclusiveLastByte` property if missing — asserts `SourcePosition` for a loose list item followed by blank line maps to the previous line's terminator, not into the blank line (the `ARC-007` +1 contract).
- `TypographyLayoutTests.codeInsideQuoteComposesBothContainers` and `nestedBlockQuotesComposeTheirRules` — same laid-out assertions, but now via typed predicate; rehearse failing by swapping a `quoteBlock()` to have non-nil background (must fail).
- `Scripts/check-proof-results.sh` rehearsal: remove one exemption from `REQUIREMENTS.md`, run gate — must report `REQ-118` unmapped/exempt failure; restore.

## Instrumentation and performance evidence

None. No runtime duration change; no new trace event.

## Failure and rollback behavior

- If identity helper encounters an unknown `NSTextBlock` (third kind), count it as neither quote nor code for composing, and continue — losing one decoration is smaller than double-counting depth. Source untouched.
- If `REQUIREMENTS.md` exemption parse fails, gate fails closed (do not fall back to hard-coded `EXEMPT`). An unparsable spec is a spec defect.
- Roll back to previous predicate/parse if any `TypographyLayoutTests` regress — the change is structural, not behavioral.

## Deletion and conformance gate

- No `backgroundColor == nil` remains outside the new identity helper.
- No second `+1` outside the single helper.
- No hard-coded `EXEMPT` remains as the source of truth.
- Delete this plan in the implementing change; Git retains history.
- Both gate scripts pass; proof-results PASS line reports `3 Done rows` + exemptions note.
