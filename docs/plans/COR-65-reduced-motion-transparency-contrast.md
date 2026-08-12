# COR-65 — Reduced Motion, Reduced Transparency, and Increase Contrast conformance

- **Status:** Approved; not implemented
- **Requirements:** new REQ-141 (the system shall introduce no motion or translucency requiring a
  Reduce Motion/Reduce Transparency accommodation, and shall express every color through the
  appearance-and-contrast-aware system catalog rather than a literal value)
- **Delivers:** REQ-141
- **ARC invariants:** new ARC-Q25 (no production animation or translucency API without a paired
  Reduce Motion/Reduce Transparency gate; no production literal color value). No architecture
  change.

## Context

Three of macOS's System Settings ▸ Accessibility ▸ Display toggles — Reduce Motion, Reduce
Transparency, and Increase Contrast — are, unlike Text Size (`COR-64`/`DISC-08`), documented,
observable, third-party-readable `NSWorkspace` properties:
`accessibilityDisplayShouldReduceMotion`, `accessibilityDisplayShouldReduceTransparency`,
`accessibilityDisplayShouldIncreaseContrast`. Source inspection
(`grep -rn "NSAnimationContext\|CABasicAnimation\|withAnimation\|animator()\.\|NSVisualEffectView"`
across `Markdown Editor/`, 2026-08-11) finds **zero** matches: the app has no animation of any kind
and no translucent chrome. Reduce Motion and Reduce Transparency therefore have nothing to
accommodate today — but nothing currently *proves* that, and nothing stops a future PR from adding
an animation without the accompanying gate.

Increase Contrast is different in kind: it is not "nothing to do" but "already handled, provided
the app never routes around it." Every color in `AttributedPresentationBuilder.swift`,
`MarkdownTheme.swift`, and `MarkdownTypography.swift` already comes from `NSColor`'s semantic
catalog (`labelColor`, `secondaryLabelColor`, `separatorColor`, `linkColor`, `quaternaryLabelColor`,
`controlAccentColor`) — these resolve to AppKit's own accessibility-high-contrast variants
automatically when Increase Contrast is on, with no application code involved. The risk is a
future literal `NSColor(red:green:blue:)`/`NSColor(srgbRed:...)`/`NSColor(white:...)` value, which
would not participate in that resolution at all.

## Production changes

None anticipated. This increment is entirely structural/absence proof, matching `COR-54`'s "this
increment is entirely verification" framing.

## Phase 1 — Reduced Motion and Reduced Transparency: absence proof plus a standing rule

```swift
// Verifies: REQ-141 — the app introduces no motion or translucency, so there is nothing for
// Reduce Motion / Reduce Transparency to accommodate; a future addition must extend this test
// rather than leave it silently passing.
@Test func noAnimationOrTranslucencyAPIIsUsedInProduction() throws {
    let forbidden = ["NSAnimationContext", "CABasicAnimation", "withAnimation(", ".animator().",
                      "NSVisualEffectView", "CAAnimation", "NSViewAnimation"]
    for file in productionSwiftFiles() {   // shared helper with COR-64's guard; factor out if both land
        let text = try String(contentsOf: file, encoding: .utf8)
        for token in forbidden {
            #expect(!text.contains(token), "\(file.lastPathComponent) uses \(token) with no Reduce Motion/Transparency gate")
        }
    }
}
```

**Rehearsed failing** by adding `NSAnimationContext.runAnimationGroup { _ in }` to a scratch
production file.

`ENGINEERING.md` §16 (Current risks) gains the standing rule this test enforces only until it is
violated: *"Any future animation or translucent view must read
`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` /
`...ShouldReduceTransparency` and degrade or omit the effect accordingly; `COR-65`'s absence test
must be replaced with a presence-of-the-gate test in the same change that adds the first instance,
never left passing vacuously."* This is written down because the test above proves absence, and an
absence proof cannot by construction also prove "and if present, gated" — that half is a reviewer
obligation until a first instance exists to test against.

## Phase 2 — Increase Contrast: no literal color value

```swift
// Verifies: REQ-141 — every production color is a semantic system color, which resolves to
// AppKit's own Increase Contrast variant automatically; a literal RGB value would not.
@Test func noProductionFileConstructsALiteralColor() throws {
    let forbidden = ["NSColor(red:", "NSColor(srgbRed:", "NSColor(calibratedRed:",
                      "NSColor(white:", "NSColor(hue:", "NSColor(cgColor:", "NSColor(deviceRed:"]
    for file in productionSwiftFiles() {
        let text = try String(contentsOf: file, encoding: .utf8)
        for token in forbidden {
            #expect(!text.contains(token), "\(file.lastPathComponent) constructs a literal color via \(token), which will not track Increase Contrast")
        }
    }
}
```

**Rehearsed failing** by adding `NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)` to a scratch
production file. `productionSwiftFiles()` scopes to `Markdown Editor/` only — `COR-63`'s
`WCAGContrast` helper legitimately constructs `NSColor(srgbRed:...)` to *resolve* an already-chosen
semantic color for measurement, and lives in `Markdown EditorTests/`, outside this guard's scope.

## Proof

- `noAnimationOrTranslucencyAPIIsUsedInProduction`, rehearsed failing.
- `noProductionFileConstructsALiteralColor`, rehearsed failing.
- Both share a `productionSwiftFiles()` helper with `COR-64`'s guard if `COR-64` has landed first;
  otherwise each defines its own copy and a hygiene pass unifies them later — no landing-order
  dependency is introduced between the two plans.

## Instrumentation and performance evidence

None — both proofs are source-text checks costing milliseconds; no runtime path is touched.

## Failure / rollback

Nothing here can affect runtime behavior. Revert is one commit.

## Deletion / conformance gate

- No production file uses an animation or translucency API without an accompanying Reduce
  Motion/Transparency gate (proved by absence today; the standing rule above governs the future
  case).
- No production file constructs a literal `NSColor`.
- `ENGINEERING.md` §16 carries the standing rule for future animation/translucency additions.
- `Scripts/check-documentation-authority.sh` and `Scripts/check-proof-results.sh` pass.
