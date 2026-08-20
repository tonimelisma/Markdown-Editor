# COR-71 Stage 0 local-transition probe

Evidence-only research for the approved COR-71 implementation plan. This file does not redefine
architecture or requirements.

- **Authority:** Evidence only
- **First researched:** 2026-08-20
- **Last verified:** 2026-08-20
- **Environment:** macOS 27.0 (Build 26A5416b), arm64 MacBook Pro, Xcode 27.0 beta,
  pinned `swift-cmark` revision `5d9bdaa4228b381639fff09403e39a04926e2dbe`.
- **Method:** a throwaway Swift Testing probe constructed real `MarkdownDocument`,
  `MarkdownParser`, `MarkdownSourceIndex`, `MarkdownProjectionModel`,
  `PresentationSnapshot`, and `SemanticEditEngine.plan` state. It submitted one visible
  insertion for each declared class and classified an accepted transition with no
  `sourceAfter` as the existing identity/local branch, an accepted transition with
  `sourceAfter` as requiring an authoritative/bounded branch, and a refusal as synchronous
  refusal. The probe was run twice; both runs passed and produced the same table. The probe was
  deleted before production implementation.
- **Refresh when:** a pinned parser revision changes; projection classification, literal encoding,
  WYSIWYG planning, or presentation-transition construction changes; or a new input class is
  added to the plan.

## Observed decision table

| Class | Observed branch | Implementation consequence |
| --- | --- | --- |
| ordinary punctuation insertion | local | Add to the closed local-transition domain. |
| delimiter insertion/removal | local | Add to the closed local-transition domain. |
| line-start marker | local | Add to the closed local-transition domain. |
| escape context | local | Add to the closed local-transition domain. |
| soft break | refusal (`unprovable`) | Refuse synchronously until a separately proven bounded transition exists. |
| hard break | refusal (`unprovable`) | Refuse synchronously until a separately proven bounded transition exists. |
| list continuation | refusal (`mappingFailure`) | Refuse synchronously; Source remains available. |
| nested quote/list | bounded-oracle-required | Use an explicit bounded enclosing-block oracle route. |
| table cell | refusal (`unprovable`) | Refuse synchronously; table-cell editing remains on its established command route. |
| raw HTML | local | Add to the local domain only for literal text that remains an uneditable/raw span. |
| code span | local | Add to the local domain only for literal code-span content. |
| code fence | local | Add to the local domain only for literal fenced content. |
| IME commit | local | Add the commit path to the local domain; composition updates/cancel remain transient. |

No observed outcome fell outside the plan's decision table. The implementation must retain the
refusal branch as a closed fallback for classes not represented above.
