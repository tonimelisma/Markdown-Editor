# COR-41 — Triage hygiene: remove hidden crash, boolean trap, and untestable geometry

- **Status:** Approved; not implemented
- **Requirements:** REQ-041/051 (highlighter within bounds), REQ-106/107 (spacing/geometry), REQ-109 (bounded patch) — no new REQ, correctness-preserving refactor
- **ARC invariants:** ARC-018/019 (typography/patch) unchanged; ARC-015 (view reconciliation) unchanged

## Context

Three low-risk hygiene defects survived the COR-26..40 sequence because each is individually small and none fails a liveness proof. Left together they raise review cost for the next product increment:

1. `MarkdownHighlighter.init` builds 12 regexes via `try! NSRegularExpression(pattern:)` (`MarkdownHighlighter.swift:25`). A malformed pattern crashes in production. Patterns are compile-time constants; failure is programmer error and should trap in DEBUG but not crash Release.
2. `WYSIWYGEditor.Coordinator.applyProjectionIfNeeded(force: Bool)` (`WYSIWYGEditor.swift:91`) is a boolean trap: two call sites pass `true`/`false` with different early-exit rules (`appliedSnapshotID != presentation.id` vs `textView.string != renderedString`). Inlining the wrong value silently changes REQ-109 recovery behavior.
3. `AttributedPresentationBuilder.installPerTextKitParagraph` (`AttributedPresentationBuilder.swift:274`) is ~70 lines of branching over TextKit paragraphs. It is correct (COR-27/36) but only indirectly tested via layout geometry; the style-array logic has no pure unit test.

No new product behavior, no new REQ, no ARC change.

## Production changes

### 1. `MarkdownHighlighter.swift` — remove `try!`

- Replace local `func re(_ pattern: String) -> NSRegularExpression { try! ... }` with a checked helper:
  ```swift
  private static func makeRegex(_ pattern: String) -> NSRegularExpression {
      do { return try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) }
      catch { preconditionFailure("invalid highlight pattern: \(pattern) — \(error)") }
  }
  ```
  Behavior identical in DEBUG (trap on invalid pattern); in Release the `preconditionFailure` still traps — the point is to remove `try!` as a hidden force-unwrap and make the failure site searchable. Alternative `try?` with fallback to `[]` would hide a programmer error; not used.

- File: `Markdown Editor/MarkdownHighlighter.swift` (init only).

### 2. `WYSIWYGEditor.swift` — replace `force: Bool` with typed reason

- Add `enum ProjectionApplyReason { case reconciliation, modeRestoration }` (or `ReapplyIfDrift` vs `NewSnapshot`) inside `WYSIWYGEditor.Coordinator`.
- Signature becomes `func applyProjectionIfNeeded(reason: ProjectionApplyReason)`.
- Call sites: `EditorHost` reconciliation → `.reconciliation`; `EditorHost` mode change / `WYSIWYGEditor` `didSet` → `.modeRestoration`.
- Early-exit rules become `switch reason` with named branches, no boolean inversion possible.
- File: `Markdown Editor/WYSIWYGEditor.swift`, `Markdown Editor/EditorHost.swift` (2 call sites).

### 3. `AttributedPresentationBuilder.swift` — extract pure installer

- Extract `private static func paragraphStyles(for block: PresentationBlock, typography: MarkdownTypography, theme: MarkdownTheme) -> [NSParagraphStyle]` or `ParagraphStyleInstaller` enum that returns the per-paragraph style array without touching `NSTextStorage`.
- `installPerTextKitParagraph` becomes `let styles = paragraphStyles(...); for (i, range) in textKitParagraphRanges.enumerated() { storage.addAttribute(.paragraphStyle, value: styles[i], range: range) }`.
- No typography change; existing `ParagraphGeometryTests` remain the layout proof, new unit test covers the style array directly (e.g. hanging indent only on first paragraph, `paragraphSpacing` only on last).

## Proof

- `Scripts/fast-check.sh` 368 passed / 0 failed (excludes PerformanceBoundaryTests per fast-check)
- Full `xcodebuild test` (Debug) — all suites must pass, including `ParagraphGeometryTests.nestedParagraphKeepsItsListItemContentIndent` and `quoteNestedInAListItemKeepsRuleAndIndent` at narrow/default/wide widths
- `Scripts/check-documentation-authority.sh` PASS
- `Scripts/check-instrumentation-coverage.sh` PASS
- `Scripts/check-proof-results.sh` PASS against the run's `.xcresult`
- New unit test: `ParagraphStyleInstallerTests` (3 cases: first paragraph has hanging indent, last has paragraphSpacing, middle has neither) — not required for REQ-118 if kept in existing suite, but will carry `// Verifies: REQ-106/107` if standalone

## Failure / rollback

Each change is a pure refactor with identical observable behavior. If any geometry test fails, revert the extracting commit; no file format or undo history change.

## Deletion / conformance gate

- No `try!` remains in `Markdown Editor/*.swift` outside `fatalError("init(coder:)")` (4 TextKit stub inits, intentional).
- No `force: Bool` or `applyProjectionIfNeeded(force:` remains — grep must be empty.
- No `installPerTextKitParagraph` with inline attribute branching — new installer is the single owner for per-paragraph style.
