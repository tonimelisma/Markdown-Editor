# COR-51 — Accessibility semantics for text constructs, and an AX audit harness

- **Status:** Approved; not implemented
- **Requirements:** REQ-032 (moves to `Correction`, then `Done` with a matrix proof), REQ-084, REQ-107; new REQ-129 (semantic blocks expose role, level and structural position)
- **Delivers:** REQ-032, REQ-084, REQ-107, REQ-129
- **ARC invariants:** new ARC-025 (every semantic block kind exposes AX semantics or a declared exemption); new ARC-Q21 (reading the accessibility tree is permitted **only** where accessibility is the requirement under test); ARC-014 (no manual or UI testing) unchanged and explicitly re-argued below

## Context

`VISION.md` states: *"Accessibility meaning does not depend on color, font weight, or visual position
alone."* In WYSIWYG today, three of nine constructs satisfy that and six do not.

| Construct | Conveyed by | AX exposure |
| --- | --- | --- |
| Task checkbox | `TaskCheckboxAttachmentCell` | role `.checkBox`, label, value, `accessibilityPerformPress` |
| Image | `ResolvedImageAttachmentCell` | role `.image`, description |
| Missing image | `MissingImageAttachmentCell` | label |
| Thematic break | `ThematicRuleAttachmentCell` | role, label |
| Heading, levels 1–6 | font size and weight only | none |
| List, item, nesting depth | indentation and marker glyph only | none |
| Blockquote | rule, inset, secondary colour | none |
| Code block | monospace and background tint | none |
| Table structure | `NSTextTable` geometry | none |

Everything backed by an attachment is done well. Everything that is *text* is conveyed exclusively by
visual attributes. A VoiceOver user cannot navigate this document by heading, which is the primary way
anyone using a screen reader moves through a document.

REQ-032 is `Done`, verified by `taskToggleSharedAcrossInteractionPaths` plus "framework inherent for
stock controls". The framework does not infer a heading from a 30 pt semibold font. The row is `Done`
on a proof covering one of nine constructs.

## Phase 0 — POC: does the attribute route actually reach VoiceOver?

`NSAttributedString.Key.accessibilityTextHeadingLevel` exists. Whether an `NSTextView` surfaces it to
an accessibility client on the target OS is an empirical question, and shipping an unverified heading
treatment would be the "asserted the attribute, not the behaviour" defect COR-27 already fixed once.

Throwaway target: construct an `NSTextView`, apply each candidate markup, force layout, and read back
**through the accessibility client API** (`accessibilityAttributedString(for:)`,
`accessibilityChildren`, `NSAccessibility.Attribute`) rather than through the storage just written.

| # | Probe |
| --- | --- |
| X1 | `.accessibilityTextHeadingLevel` on a range — does the client report a heading level? |
| X2 | `.accessibilityLabel` on a single character — is it announced, and does it suppress the character? |
| X3 | `NSAccessibilityElement` children added to the text view — do they coexist with ordinary text navigation? |
| X4 | `NSTextTable` cells — does the client report row and column structure natively? |
| X5 | `.accessibilitySpeechPunctuation` inside a code block — honoured? |

### Decision table — applied mechanically

| Observation | Branch |
| --- | --- |
| X1 reports the level | headings use the attribute route — simplest, and text navigation stays intact |
| X1 does not report | headings use `NSAccessibilityElement` children (per X3), one per heading; record the element-tree cost |
| X2 suppresses the character | labels move to a zero-width adjacent position; record the technique |
| X4 native | tables need nothing |
| X4 not native | add per-cell labels: `"Column header, X"` and `"Row n, X, value"` |
| X5 not honoured | drop it and record that code punctuation relies on the user's own VoiceOver verbosity setting |

**Then, without stopping:** write `docs/research/DISC-06-textview-accessibility.md` (evidence-only
authority, dates, macOS and SDK versions, method, probe outputs, branch taken, refresh triggers),
delete the POC, rewrite Phase 1 to match, commit, and continue.

## Phase 1 — markup per block kind

Applied in `AttributedPresentationBuilder.apply(block:localRange:to:typography:)`.

| Kind | Exposure |
| --- | --- |
| `.heading(level)` | heading role and level, by the route Phase 0 selected |
| `.listItem(_, nesting, task)` | `"Level \(nesting + 1) item"` on the marker range; task items keep the checkbox cell's role and value |
| `.blockQuote(depth)` | `"Quote, level \(depth)"` |
| `.codeBlock` | `"Code block"`, plus punctuation handling per X5 |
| `.literalHTML` | `"Literal HTML, not rendered"` |
| `.table`, `.tableRow`, `.tableCell` | per X4 |
| `.paragraph` | exempt — ordinary prose |
| `.image`, `.thematicBreak` | exempt — attachment-backed and already covered |

Exemptions and their reasons live in `REQUIREMENTS.md` beside REQ-032 and are **read by the test**,
the same spec-is-source-of-truth pattern COR-39 established for `check-proof-results.sh`'s `EXEMPT`
list. A reason that exists only in a code comment is not an exemption.

## Phase 2 — the closed matrix

```swift
/// Closed matrix over every semantic block kind. A new kind fails the build until its accessibility
/// is declared — the forcing function `CommandLivenessMatrixTests` already applies to commands.
@Test(arguments: PresentationBlockKindCase.allCases)
func everySemanticBlockKindDeclaresItsAccessibility(_ kind: PresentationBlockKindCase) throws
```

`PresentationBlockKindCase` is a `CaseIterable` mirror of `PresentationBlock.Kind` without associated
values, tied to the real enum by an exhaustive `switch` in `mirror(of:)` so that adding a kind fails
to **compile** until it is mapped, and then fails the **test** until its accessibility is declared.

## Phase 3 — the AX audit harness

`Scripts/ax-audit.sh` runs the built application in benchmark mode over `Scripts/Fixtures/smoke-rich.md`,
walks the accessibility tree of the document window, and emits a structured report:

```text
heading level=1 "Typography proof"
paragraph "Paragraph one, long enough…"
list level=1 items=2
  listItem level=1 "Unordered item"
```

Committed as `Tests/Goldens/ax-smoke-rich.txt` and diffed on every run. This is what closes the loop:
an accessibility claim becomes a reviewable artifact in the PR diff rather than a checkbox in a table.

**The tension with `CLAUDE.md` §4, resolved explicitly rather than left implicit.** Reading the
accessibility tree uses an accessibility API, which §4 names when forbidding UI verification. What §4
forbids is using AX to drive or assert on the UI *as a substitute for a real proof*. Here accessibility
**is** the subject under test; there is no other way to verify an accessibility requirement, and
refusing would make accessibility the one requirement class this project structurally cannot prove.
This is recorded as a third narrow carve-out, ARC-Q21, in those words, alongside ARC-Q12 and ARC-Q13 —
never as a quiet reinterpretation of an existing rule. Nothing is driven, no synthetic event is
dispatched, and no pixel is read.

## Proof

- `everySemanticBlockKindDeclaresItsAccessibility` — the closed matrix. **Rehearsed failing** by
  adding a kind without a declaration.
- `headingsExposeTheirLevelToAnAccessibilityClient` — construct the view, force layout, read back
  through the client API. **Rehearsed failing** against today's build, which reports no level.
- `listItemsExposeTheirNestingDepth`, `blockQuotesExposeTheirDepth`,
  `codeBlocksAnnounceThemselvesAsCode`, `literalHTMLAnnouncesThatItIsNotRendered`.
- `tableCellsExposeRowAndColumnPosition` — or, per X4, an assertion that the framework already does.
- `accessibilityExemptionsAreDeclaredInRequirements` — the exemption list is read from
  `REQUIREMENTS.md`, so a code-only exemption fails.
- `axAuditGoldenMatches` — the committed report diff.
- Existing `taskToggleSharedAcrossInteractionPaths` and the attachment-cell proofs stay green.

## Instrumentation and performance evidence

Attributed-string attributes are added during `buildScoped`, which is on the keystroke path. Confirm no
regression in `nativeInputCallback` p95 on the `structuredProse` and `heavyLists` corpora, and record
the delta. If the element-tree branch (X1 negative) is taken, measure it explicitly — an element per
heading in a 100k document is a real cost and must be a measured one.

## Failure / rollback

Additive and presentation-only; nothing here can alter source bytes or coordinates. The realistic
failure is a label that reads badly in practice, which the AX audit golden surfaces as reviewable text.

If Phase 0 finds no route that reaches a client for headings, the increment still lands the matrix,
the exemption mechanism, the audit harness, and every construct that does work — and REQ-032 stays
`Correction` for headings alone, with the probe output recorded. Partial coverage that is honestly
declared is a better outcome than a `Done` row covering one construct in nine.

## Deletion / conformance gate

- No construct conveys meaning by font, colour or position alone without a declared exemption; ARC-025
  is proved by the matrix, not by inspection.
- The two `setAccessibilityLabel` calls on the text views (`"Markdown source"`, `"Markdown WYSIWYG"`)
  remain container labels and are no longer the whole of the app's accessibility story.
- `Scripts/check-documentation-authority.sh`, `Scripts/check-instrumentation-coverage.sh` and
  `Scripts/check-proof-results.sh` pass.
