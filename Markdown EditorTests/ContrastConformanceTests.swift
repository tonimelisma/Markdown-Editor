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

    // Verifies: REQ-139/141 — a colour made in one appearance is the right colour in another, as a
    // page built in Light and shown after a switch to Dark has. Quote text was made with a fixed
    // alpha copy of the label colour and stayed near-black in Dark (tour 45974231615). The other
    // tests make each colour inside the appearance they measure, so they could not see it.
    @Test func everyColorRoleFollowsAnAppearanceChangeMadeAfterIt() {
        for role in EditorColorRole.allCases {
            var madeInLight: NSColor?
            withAppearance(.aqua) { madeInLight = EditorColorCatalog.color(role) }
            var lightInDark: NSColor?
            var madeInDark: NSColor?
            withAppearance(.darkAqua) {
                lightInDark = madeInLight?.usingColorSpace(.sRGB)
                madeInDark = EditorColorCatalog.color(role).usingColorSpace(.sRGB)
            }
            guard let lightInDark, let madeInDark else {
                Issue.record("\(role) did not resolve")
                continue
            }
            let apart = abs(lightInDark.redComponent - madeInDark.redComponent)
                + abs(lightInDark.greenComponent - madeInDark.greenComponent)
                + abs(lightInDark.blueComponent - madeInDark.blueComponent)
                + abs(lightInDark.alphaComponent - madeInDark.alphaComponent)
            #expect(apart < 0.01, "\(role) made in Light resolves in Dark to \(lightInDark), not \(madeInDark)")

            // The same for a role drawn at an alpha, as the code background is.
            var fillInLight: NSColor?
            withAppearance(.aqua) { fillInLight = EditorColorCatalog.color(role, alpha: 0.5) }
            var fillLightInDark: NSColor?
            var fillMadeInDark: NSColor?
            withAppearance(.darkAqua) {
                fillLightInDark = fillInLight?.usingColorSpace(.sRGB)
                fillMadeInDark = EditorColorCatalog.color(role, alpha: 0.5).usingColorSpace(.sRGB)
            }
            if let a = fillLightInDark, let b = fillMadeInDark {
                let fillApart = abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent)
                    + abs(a.blueComponent - b.blueComponent) + abs(a.alphaComponent - b.alphaComponent)
                #expect(fillApart < 0.01, "\(role) at an alpha, made in Light, resolves in Dark to \(a), not \(b)")
            } else {
                Issue.record("\(role) at an alpha did not resolve")
            }
        }
    }

    // Verifies: REQ-139 — every declared colour role meets its WCAG 2.1 bound against the surface
    // it is drawn on, in Light and Dark. The enumeration is `EditorColorRole.allCases`, so a new
    // role fails this test until its contrast is measured: the requirement quantifies over "any
    // declared semantic color role", which a hand-picked list of three would not discharge.
    //
    // This carried a pinned `knownContrastViolations` set of three until COR-85. The set is deleted
    // rather than emptied, because conformance is now an assertion and not a place to park a defect.
    @Test func everyColorRoleMeetsItsContrastBound() {
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
            violations.isEmpty,
            """
            \(violations.count) colour role(s) below their WCAG bound: \(violations.sorted())
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
