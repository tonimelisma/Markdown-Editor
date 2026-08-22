//
//  ContrastConformanceTests.swift
//  Markdown EditorTests
//
//  COR-81 / REQ-139: WCAG 2.1 contrast over the declared colour catalog, in every appearance.
//

import AppKit
import Testing
@testable import Markdown_Editor

@MainActor
struct ContrastConformanceTests {

    /// WCAG 2.1 relative luminance. Written out rather than taken from a helper the catalog also
    /// uses, so this is an independent calculation and not the product agreeing with itself.
    private func relativeLuminance(_ color: NSColor) -> Double {
        guard let srgb = color.usingColorSpace(.sRGB) else {
            Issue.record("colour could not be resolved into sRGB: \(color)")
            return 0
        }
        func channel(_ value: CGFloat) -> Double {
            let c = Double(value)
            return c <= 0.039_28 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(srgb.redComponent)
             + 0.7152 * channel(srgb.greenComponent)
             + 0.0722 * channel(srgb.blueComponent)
    }

    private func contrastRatio(_ foreground: NSColor, on background: NSColor) -> Double {
        // Semantic label colours carry alpha; composite onto the background before measuring,
        // because that is what the eye receives. Measuring the un-composited colour reports a
        // ratio the user never sees.
        let composited = composite(foreground, over: background)
        let a = relativeLuminance(composited)
        let b = relativeLuminance(background)
        let lighter = max(a, b), darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func composite(_ foreground: NSColor, over background: NSColor) -> NSColor {
        guard let f = foreground.usingColorSpace(.sRGB), let b = background.usingColorSpace(.sRGB) else {
            return foreground
        }
        let alpha = f.alphaComponent
        guard alpha < 1 else { return f }
        return NSColor(
            srgbRed: f.redComponent * alpha + b.redComponent * (1 - alpha),
            green: f.greenComponent * alpha + b.greenComponent * (1 - alpha),
            blue: f.blueComponent * alpha + b.blueComponent * (1 - alpha),
            alpha: 1
        )
    }

    private func withAppearance(_ name: NSAppearance.Name, _ body: () -> Void) {
        let previous = NSAppearance.currentDrawing()
        guard let appearance = NSAppearance(named: name) else {
            Issue.record("appearance \(name.rawValue) unavailable")
            return
        }
        appearance.performAsCurrentDrawingAppearance(body)
        _ = previous
    }

    /// Roles that do **not** currently meet their WCAG 2.1 bound, with the measured ratio.
    ///
    /// Pinned rather than excluded, for the reason given in `PropertyTests`: a filter only fails
    /// when things get worse, while a baseline also fails when they get better and so forces the
    /// list down in the same change that fixes anything.
    ///
    /// Both entries are real and are recorded in `docs/research/COR-81-contrast-conformance.md`:
    ///
    /// - `secondaryText` in Light is 3.95:1 against the window background, below the 4.5:1 bound
    ///   for normal text. It carries block-quote text, table header text and list markers.
    /// - `separator` is 1.25:1 in Light and 1.34:1 in Dark, far below the 3:1 component bound. It
    ///   draws thematic breaks and table borders, which are *content* — `---` is a Markdown
    ///   construct the reader is meant to perceive — not decoration.
    ///
    /// Fixing either needs a product decision about the approved appearance, which VISION owns, so
    /// REQ-139 is `Correction` with a reproduced counterexample rather than `Done`.
    private static let knownContrastViolations: Set<String> = [
        "secondaryText@NSAppearanceNameAqua",
        "separator@NSAppearanceNameAqua",
        "separator@NSAppearanceNameDarkAqua"
    ]

    // Verifies: REQ-139 — every declared colour role is measured against the surface it is drawn
    // on, in Light and Dark, and the set of roles failing their WCAG bound is exactly the pinned
    // set. The enumeration is `EditorColorRole.allCases`, so a new role fails this test until its
    // contrast is measured: the requirement quantifies over "any declared semantic color role",
    // which a hand-picked list of three would not discharge.
    @Test func colorRoleContrastMatchesTheDeclaredConformanceSet() {
        var violations: Set<String> = []
        var measured: [String] = []

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            withAppearance(appearanceName) {
                let background = EditorColorCatalog.windowBackground
                for role in EditorColorRole.allCases {
                    // `codeBackground` is a surface rather than a mark; it is measured as the
                    // ground for code text in `codeTextMeetsContrastOnTheCodeBackground`.
                    guard role != .codeBackground else { continue }
                    let ratio = contrastRatio(EditorColorCatalog.color(role), on: background)
                    let bound = role.isTextRole ? 4.5 : 3.0
                    let key = "\(role.rawValue)@\(appearanceName.rawValue)"
                    measured.append("\(key)=\(String(format: "%.2f", ratio)) bound=\(bound)")
                    if ratio < bound { violations.insert(key) }
                }
            }
        }

        #expect(
            violations == Self.knownContrastViolations,
            """
            contrast conformance changed.
            unexpected new violations: \(violations.subtracting(Self.knownContrastViolations).sorted())
            fixed (remove from the pinned set): \(Self.knownContrastViolations.subtracting(violations).sorted())
            measured: \(measured.sorted().joined(separator: ", "))
            """
        )
    }

    // Verifies: REQ-139 — code text stays legible on the code background, which is the composition
    // the ordinary-background test cannot see: `codeBackground` is translucent, so code text is
    // measured against quaternary-over-window rather than against the window.
    @Test func codeTextMeetsContrastOnTheCodeBackground() {
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            withAppearance(appearanceName) {
                let surface = composite(
                    EditorColorCatalog.color(.codeBackground),
                    over: EditorColorCatalog.windowBackground
                )
                let ratio = contrastRatio(EditorColorCatalog.color(.primaryText), on: surface)
                #expect(
                    ratio >= 4.5,
                    "code text in \(appearanceName.rawValue): \(String(format: "%.2f", ratio)):1 < 4.5:1"
                )
            }
        }
    }

    // Verifies: REQ-139 — Increase Contrast never *reduces* contrast for any role. The accessibility
    // appearance is a different resolution of the same semantic colours, and a regression there is
    // invisible to the two tests above.
    @Test func increasedContrastNeverLowersAnyRolesRatio() {
        for base in [NSAppearance.Name.aqua, .darkAqua] {
            let increased: NSAppearance.Name = base == .aqua ? .accessibilityHighContrastAqua : .accessibilityHighContrastDarkAqua
            var ordinary: [EditorColorRole: Double] = [:]
            var contrasted: [EditorColorRole: Double] = [:]

            withAppearance(base) {
                let background = EditorColorCatalog.windowBackground
                for role in EditorColorRole.allCases {
                    ordinary[role] = contrastRatio(EditorColorCatalog.color(role), on: background)
                }
            }
            withAppearance(increased) {
                let background = EditorColorCatalog.windowBackground
                for role in EditorColorRole.allCases {
                    contrasted[role] = contrastRatio(EditorColorCatalog.color(role), on: background)
                }
            }

            for role in EditorColorRole.allCases {
                let before = ordinary[role] ?? 0
                let after = contrasted[role] ?? 0
                // Small tolerance: some system colours are identical across the pair.
                #expect(
                    after >= before - 0.01,
                    "\(role.rawValue): Increase Contrast lowered \(String(format: "%.2f", before)) to \(String(format: "%.2f", after)) in \(base.rawValue)"
                )
            }
        }
    }
}
