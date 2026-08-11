# COR-50 — Semantic bullets in WYSIWYG

- **Status:** Approved; not implemented
- **Requirements:** REQ-054 (render every supported construct), REQ-056 (omit parsed control characters), REQ-057 (smallest proven unit), REQ-078 (task checkbox), REQ-107 (approved semantic block treatment)
- **Delivers:** REQ-054, REQ-056, REQ-057, REQ-078, REQ-107
- **ARC invariants:** ARC-007 (exact conversion) and ARC-009 (refusal) unchanged. `ENGINEERING.md` §6 is amended to state that a list marker is an atomic atom whose *displayed* glyph is semantic and whose *source* spelling is carried, not shown — a clarification of an existing case, not a new one.

## Context

`ProjectionCompiler.markerGlyph` (`ProjectionCompiler.swift:577`) returns the literal source
character:

```swift
case .dash: return "-"
case .plus: return "+"
case .asterisk: return "*"
```

The August window capture shows `- Unordered item`. The same semantic list therefore renders three
different ways depending on how the author spelled it, and a parsed delimiter is visible in a surface
`VISION.md` defines as showing "formatted content **without parsed Markdown delimiters**". `**bold**`
hides its delimiters; `- item` does not.

The cause looks like a conflation: `ENGINEERING.md` §6 correctly requires that an editable synthetic
control carry "its exact source representation", and the marker was therefore *displayed* as its
source representation too. Those are separable — carrying the spelling is what the coordinate map and
the planners need; showing it is a rendering decision that nothing requires.

This is the most visible gap between the current render and something that looks like Apple shipped it.

## Phase 0 — POC: choose the glyph by looking at it

Bullets are a typography problem. `•` at 15 pt in the system font is optically large and sits high on
the line, and guessing is what produced the caret-shaped checkmark COR-22 had to fix by screenshot.

Throwaway: render each candidate into a directly constructed, laid-out `NSTextView` at the 15 pt body
size over a three-level nested list, capture with the existing window-only mechanism, and look.

| Level | Candidates |
| --- | --- |
| 1 | `•` U+2022 at 100 % and at 85 % of body size; `●` U+25CF at 60 % |
| 2 | `◦` U+25E6; `▫` U+25AB; `–` U+2013 |
| 3 | `▪` U+25AA; `‣` U+2023; `•` at 70 % |
| colour | `labelColor`, `secondaryLabelColor`, `tertiaryLabelColor` |

### Decision table — applied mechanically

| Observation | Action |
| --- | --- |
| A candidate is optically centred on the x-height and does not dominate the item text | adopt it |
| Every level-1 candidate reads too heavy at `labelColor` | adopt `secondaryLabelColor` for markers at all levels |
| No candidate sits correctly at 100 % body size | adopt a scaled marker font and record the scale as a `MarkdownTypography` token, never as a literal at the call site |
| POC inconclusive | default to `•` / `◦` / `▪` cycling by depth, 100 % body size, `secondaryLabelColor` — matching Notes and Pages |

**Then, without stopping:** write `docs/research/DISC-05-list-marker-typography.md` (evidence-only
authority, dates, method, captures described, choice made), delete the POC, rewrite Phases 1–3 with
the chosen values, add them to `ENGINEERING.md` §7's token table so they are approved tokens rather
than constants someone typed, commit, and continue.

## Phase 1 — the glyph becomes semantic

```swift
/// The *displayed* bullet. Nesting-cyclic like every native outline, so nested levels stay
/// distinguishable without depending on which character the author happened to type.
///
/// The source spelling is not lost: it travels on the marker's `.listMarker` atom, which is what the
/// coordinate map and the editing planners use. Displaying the source character here made one
/// semantic list render three different ways.
func markerGlyph(_ marker: MarkdownListMarker, nesting: Int) -> String
```

Ordered markers are unchanged. The number is content rather than a delimiter, and matching the
author's `.` versus `)` is invisible to a reader.

## Phase 2 — split the two meanings of `markerText`

`PresentationBlock.Kind` and the projection segment currently carry one `markerText` string used both
as displayed text and as source spelling:

```swift
case listMarker(displayed: String, source: String, nesting: Int)
```

Every consumer reading it for **source** purposes — `StructuralSourceSpans`, `ListEditPlanner`,
`ProjectionSelectionClassifier` — reads `source`. Every consumer reading it for **length or geometry**
reads `displayed`. Fix the compile errors one at a time; there is no ambiguous case, which is the
point of splitting rather than adding a computed alias.

`-`, `*`, `+`, `•`, `◦` and `▪` are each one UTF-16 unit, so marker text stays `glyph + " "` at
length 2 and no coordinate arithmetic changes. **Assert this rather than depending on it**: if
Phase 0 selects a multi-unit glyph, the atom's decoder and encoder must handle the length change,
which is precisely what an atomic atom exists for.

## Phase 3 — a task item keeps exactly one marker

`ENGINEERING.md` §7 requires a checkbox to *replace* the ordinary bullet. Verify after the change that
the task attachment path does not now emit both a `•` and a checkbox.

## Proof

- `unorderedListsRenderTheSameBulletForEverySourceSpelling`, parameterised over `["-", "*", "+"]`:
  parse `"<marker> alpha\n<marker> beta\n"` for each and assert `renderedString` is byte-identical
  across all three. **Rehearsed failing** — today it produces three different strings. This is the
  increment's headline proof.
- `editingAListItemPreservesItsSourceMarkerSpelling`, same parameterisation: an accepted edit inside
  the item leaves the source marker character unchanged, so a `*`-spelled document stays `*`-spelled.
- `nestedBulletsUseDistinctGlyphsPerDepth` — depth is distinguishable without relying on colour or
  size alone (VISION's accessibility rule applied to rendering).
- `taskItemsShowNoOrdinaryBullet`.
- `markerBaselineMatchesItsItemText` — forces layout on a directly constructed `NSTextView` and
  compares the marker glyph's line-fragment baseline against the item text's. Laid-out geometry, per
  `CLAUDE.md` §4's rule that a claim about what the reader sees is proved by layout, not by attribute
  values.
- `markerAtomLengthMatchesItsDisplayedGlyph` — the assertion that keeps Phase 2's convenient
  single-unit property honest.

`Scripts/Fixtures/smoke-rich.md` gains a `*`-spelled and a `+`-spelled list so REQ-104's visual review
can see this class at all; it currently cannot.

## Instrumentation and performance evidence

None new. The change is a string substitution inside projection compilation with no additional work
per block; confirm no regression in `parseProjection` p95 on the `heavyLists` corpus.

## Failure / rollback

The risk is coordinate drift: the marker is an editable atom, and if `displayed` and `source` are
crossed at any call site, an edit near a list marker could map to the wrong source range. Controls:
the split is a compile error at every call site rather than a silent behaviour change; the oracle
validates every snapshot; and `editingAListItemPreservesItsSourceMarkerSpelling` plus the existing
`selectionStartingOnListMarkerMapsToSource` prove the mapping end to end.

Revert is one commit. Nothing persists — the change is presentation-only and cannot alter a saved file.

## Deletion / conformance gate

- No production path returns a source marker character for display; `markerGlyph`'s only caller is the
  displayed field.
- The single-field `markerText` no longer exists, so no call site can read the wrong meaning by
  accident.
- `Scripts/check-documentation-authority.sh` passes with `ENGINEERING.md` §6 and §7 updated in the
  same change.
