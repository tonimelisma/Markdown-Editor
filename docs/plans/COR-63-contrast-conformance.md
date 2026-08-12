# COR-63 — WCAG AA contrast conformance for every declared color role

- **Status:** Approved; not implemented
- **Requirements:** new REQ-139 (every color pairing the app declares meets WCAG 2.1 AA contrast in
  both appearances)
- **Delivers:** REQ-139
- **ARC invariants:** new ARC-Q23 (closed matrix over every declared foreground/background color
  role, Light and Dark, meets its WCAG threshold). No architecture change: this is a new quality
  scenario alongside `ARC-Q14`, not a redefinition of it.

## Context

`ARC-Q14` proves that Light and Dark appearance each resolve to *a* color for every semantic
style. Nothing proves those colors are legible together. `COR-52`'s layout goldens deliberately
serialize colors as semantic names ("`labelColor`, `separatorColor`, never RGBA — RGBA legitimately
changes with appearance and OS version") — the right call for golden stability, but it means no
existing or planned proof ever resolves a color to concrete numbers and checks anything about them.
Contrast is a numeric property; it needs a numeric proof, kept separate from the golden mechanism
that exists to avoid numeric brittleness.

Source inspection (`AttributedPresentationBuilder.swift`, `MarkdownTheme.swift`,
`MarkdownTypography.swift`) finds every color already comes from `NSColor`'s semantic system
catalog — `labelColor`, `secondaryLabelColor`, `linkColor`, `separatorColor`,
`quaternaryLabelColor`, `controlAccentColor` — never a literal RGB value, and `WYSIWYGEditor.swift`
/ `SourceEditor.swift` set neither `backgroundColor` nor `drawsBackground` on either text view, so
both inherit `NSTextView`'s default `textBackgroundColor`. This is good practice — semantic colors
are Apple's own contrast-aware pairings — but "good practice" is not a proof, and `secondaryLabelColor`
is documented as a reduced-opacity variant of `labelColor` specifically because it is allowed to be
*less* legible than body text; nothing today asserts it stays above any floor.

## Phase 1 — the contrast math

New `Markdown EditorTests/WCAGContrast.swift`, test-only (no production dependency):

```swift
/// WCAG 2.1 relative luminance and contrast ratio, computed in the sRGB space `NSColor.usingColorSpace(.sRGB)` returns.
enum WCAGContrast {
    static func relativeLuminance(_ color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.sRGB)!
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(Double(rgb.redComponent))
             + 0.7152 * linear(Double(rgb.greenComponent))
             + 0.0722 * linear(Double(rgb.blueComponent))
    }

    /// Ratio of the lighter to the darker relative luminance, per WCAG 2.1 §1.4.3.
    static func ratio(_ a: NSColor, _ b: NSColor) -> Double {
        let (l1, l2) = (relativeLuminance(a), relativeLuminance(b))
        let (lighter, darker) = l1 >= l2 ? (l1, l2) : (l2, l1)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Alpha-over compositing of `overlay` atop `base`, both already resolved in the same
    /// appearance and color space. Required before computing luminance for any attribute that
    /// carries alpha (e.g. `.quaternaryLabelColor.withAlphaComponent(0.18)`), since luminance of
    /// an unpremultiplied translucent color alone does not describe what the eye sees.
    static func composited(_ overlay: NSColor, over base: NSColor) -> NSColor {
        let o = overlay.usingColorSpace(.sRGB)!
        let b = base.usingColorSpace(.sRGB)!
        let a = Double(o.alphaComponent)
        func mix(_ fg: CGFloat, _ bg: CGFloat) -> CGFloat { CGFloat(Double(fg) * a + Double(bg) * (1 - a)) }
        return NSColor(srgbRed: mix(o.redComponent, b.redComponent),
                        green: mix(o.greenComponent, b.greenComponent),
                        blue: mix(o.blueComponent, b.blueComponent), alpha: 1)
    }

    /// WCAG 2.1 §1.4.3: 3:1 for text at least 18pt, or at least 14pt and bold; 4.5:1 otherwise.
    /// §1.4.11: 3:1 for non-text UI components/graphical objects, unconditionally.
    static func requiredRatio(isText: Bool, pointSize: CGFloat, isBold: Bool) -> Double {
        guard isText else { return 3.0 }
        return (pointSize >= 18 || (pointSize >= 14 && isBold)) ? 3.0 : 4.5
    }
}
```

`requiredRatio` derives the large-text exemption from the **actual resolved font** at test time
rather than from an assumed heading size — `MarkdownTypography`'s per-level point sizes are read
through `NSFont.pointSize` and `NSFontDescriptor.symbolicTraits.contains(.bold)`, never restated,
so a future typography change cannot silently invalidate an assumption baked into this test.

## Phase 2 — the closed matrix of color roles

`PresentationColorRole`, a `CaseIterable` enum mirroring every place `AttributedPresentationBuilder`
(WYSIWYG) or `MarkdownTheme`/`MarkdownHighlighter` (Source) sets `.foregroundColor`,
`.backgroundColor`, `setBorderColor`, `setStroke`, or `setFill`, tied to the real call sites by an
exhaustive `switch` the same way `COR-51`'s `PresentationBlockKindCase` ties to `PresentationBlock.Kind`
— adding a new colored role fails to *compile* until mapped here, and fails the *test* in Phase 3
until its contrast is proven. (This plan defines its own mirror rather than depending on `COR-51`'s
`PresentationBlockKindCase`, so the two increments carry no landing-order dependency; if `COR-51` has
already landed, a future hygiene pass may unify them.)

```swift
enum PresentationColorRole: CaseIterable {
    case sourceHeadingText, sourceInlineCodeText, sourceCodeBlockText, sourceLinkText
    case sourceBlockquoteMarkerText, sourceListMarkerText   // MarkdownTheme's remaining secondaryLabelColor sites
    case wysiwygBodyText, wysiwygHeadingText, wysiwygBlockquoteText, wysiwygLinkText
    case wysiwygCodeBlockText, wysiwygMissingImagePlaceholderText
    case wysiwygCodeBlockBackground, wysiwygMissingImagePlaceholderBackground   // non-text: fills
    case wysiwygBlockquoteRule, wysiwygThematicBreakRule, wysiwygTableBorder    // non-text: strokes
    case wysiwygImageSelectionAccent                                            // non-text: stroke

    var isText: Bool { /* false for the six non-text cases listed above */ }
    var backgroundIsComposited: Bool { self == .wysiwygCodeBlockText || self == .sourceCodeBlockText }
}
```

Exact site correspondence is fixed by reading current source line-for-line at implementation time
(`AttributedPresentationBuilder.swift:147,156,182,214,249,341,445,493,497,533`;
`MarkdownTheme.swift:21,29,35,39-40,43,45,48`) — the enumeration above names every case the current
grep already found; implementation must re-derive it from the file at HEAD rather than trust this
list if the files have changed since 2026-08-11.

Each case resolves to `(foreground: NSColor, background: NSColor, font: NSFont?)` by constructing
the real object that carries it (`MarkdownTypography()`, `MarkdownTheme.attributes(for:)`, or a
built `AttributedPresentationBuilder` snapshot over a minimal fixture exercising that construct) and
reading the attribute back — never by re-typing the color name, which would let the test and the
production code drift independently and both still pass.

## Phase 3 — the proof

```swift
// Verifies: REQ-139 — every declared color role meets its WCAG 2.1 threshold in both appearances.
@Test(arguments: PresentationColorRole.allCases, [NSAppearance(named: .aqua)!, NSAppearance(named: .darkAqua)!])
func colorRoleMeetsItsContrastThreshold(_ role: PresentationColorRole, _ appearance: NSAppearance) throws {
    var ratio: Double = 0
    var required: Double = 0
    appearance.performAsCurrentDrawingAppearance {
        let resolved = role.resolve()   // (fg, bg, font) per Phase 2
        let bg = role.backgroundIsComposited
            ? WCAGContrast.composited(resolved.background, over: NSColor.textBackgroundColor)
            : resolved.background
        required = WCAGContrast.requiredRatio(
            isText: role.isText,
            pointSize: resolved.font?.pointSize ?? 15,
            isBold: resolved.font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
        ratio = WCAGContrast.ratio(resolved.foreground, bg)
    }
    #expect(ratio >= required, "\(role): \(ratio) < required \(required)")
}
```

This reuses `TypographyLayoutTests.semanticTreatmentsResolveInLightAndDark`'s exact
`NSAppearance(named:).performAsCurrentDrawingAppearance` pattern — the established mechanism for
forcing a specific appearance's color resolution in this suite — rather than introducing a second
one.

## Expected outcome

Not predicted in advance. `NSColor`'s semantic catalog is Apple's own contrast-aware pairing and is
likely to pass most or all roles, but `secondaryLabelColor` and the 0.18-alpha code-block tint are
exactly the kind of "probably fine" the rest of this repository's evidence floor exists to stop
assuming. If a role fails, `REQ-139` lands `Correction` with the measured ratio and required
threshold recorded per role, and the color fix is scoped as a follow-up — this increment's job is
the measurement, matching `COR-45`'s and `COR-54`'s precedent of landing verification work whose
outcome is unknown until it runs.

## Instrumentation and performance evidence

None of this touches the keystroke path; every resolution happens in test code against constructed
objects or minimal fixtures. No production code changes.

## Failure / rollback

Verification-only; nothing ships. Revert is one commit. The only production risk is if a discovered
failure is fixed in the same increment — if so, scope that fix to the smallest color substitution
(e.g. `secondaryLabelColor` → `labelColor` for one role) and re-run the full matrix, since a color
change can move other roles that share the same background.

**Rehearsed failing (`CLAUDE.md` §9):** temporarily hard-code `wysiwygMissingImagePlaceholderText`'s
resolved foreground to `NSColor(white: 0.85, alpha: 1)` against its `quaternaryLabelColor` fill —
`colorRoleMeetsItsContrastThreshold` must turn red for that case and only that case before this
proof is trusted.

## Deletion / conformance gate

- No color role resolves its comparison by re-typing a semantic color's name; every resolution
  reads the real attribute-producing call.
- `backgroundIsComposited` covers every role whose background attribute carries alpha; a new
  alpha-bearing role added without setting it produces a wrong (uncomposited) ratio, which is a
  latent defect this plan records rather than silently accepts — a follow-up structural check
  (assert `backgroundColor.alphaComponent == 1` for every role not flagged) is left as a documented
  gap if not closed in this increment.
- `Scripts/check-documentation-authority.sh` and `Scripts/check-proof-results.sh` pass.
