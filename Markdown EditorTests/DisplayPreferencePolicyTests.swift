//
//  DisplayPreferencePolicyTests.swift
//  Markdown EditorTests
//
//  COR-81 / REQ-141: motion, translucency, and colour-literal policy.
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

struct DisplayPreferencePolicyTests {

    private func productionSources() throws -> [(name: String, text: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Markdown Editor")
        let urls = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "swift" }
        #expect(!urls.isEmpty, "no production sources found")
        return try urls.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// This is an *absence* proof, which `CLAUDE.md` §3 permits source inspection for — and it
    /// verifies its own detector below rather than trusting that the pattern would have matched.
    private func colorLiteralHits(in text: String) -> [String] {
        let patterns = [
            #"NSColor\s*\("#,                    // component initialisers
            #"NSColor\.(?!clear\b)[a-z]"#,       // named system colours outside the catalog
            #"Color\(\s*red:"#,                  // SwiftUI component initialiser
            #"#colorLiteral"#
        ]
        var hits: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = text as NSString
            regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match else { return }
                let line = ns.substring(with: ns.lineRange(for: match.range))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("//") || line.hasPrefix("///") { return }
                hits.append(line)
            }
        }
        return hits
    }

    // Validates: REQ-141 — production expresses colour only through `EditorColorCatalog`. A literal
    // or a bare system colour anywhere else escapes the appearance-and-contrast-aware catalog, and
    // with it every measurement in `ContrastConformanceTests` — which can only enumerate roles it
    // knows about.
    @Test func productionNamesNoColorOutsideTheCatalog() throws {
        for (name, text) in try productionSources() where name != "EditorColorCatalog.swift" {
            let hits = colorLiteralHits(in: text)
            #expect(hits.isEmpty, "colour named outside EditorColorCatalog in \(name): \(hits)")
        }
    }

    // Validates: REQ-141 — the detector above actually detects. An absence proof whose pattern never
    // matches anything is indistinguishable from a codebase that is clean, which is how
    // `check-instrumentation-coverage.sh` was defeated twice (see ADR 0001).
    @Test func theColorLiteralDetectorCatchesEveryFormItClaimsTo() {
        let shouldMatch = [
            "let c = NSColor(red: 1, green: 0, blue: 0, alpha: 1)",
            "attrs[.foregroundColor] = NSColor.systemPink",
            "let c = Color(red: 0.1, green: 0.2, blue: 0.3)",
            "let c = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)"
        ]
        for line in shouldMatch {
            #expect(!colorLiteralHits(in: line).isEmpty, "detector missed: \(line)")
        }

        let shouldNotMatch = [
            "let c = EditorColorCatalog.color(.primaryText)",
            "// NSColor.labelColor is resolved through the catalog",
            "NSColor.clear.setFill()"
        ]
        for line in shouldNotMatch {
            #expect(colorLiteralHits(in: line).isEmpty, "detector false-positived: \(line)")
        }
    }

    // Validates: REQ-141 — no motion or translucency is introduced without a paired Reduce Motion /
    // Reduce Transparency accommodation. Today the editor animates and blurs nothing, so this is an
    // absence proof; the point is that adding one fails here until the accommodation exists beside
    // it, rather than being noticed by whoever has the preference turned on.
    @Test func motionAndTranslucencyRequirePairedAccommodations() throws {
        let motionAPIs = [
            "NSAnimationContext", "CABasicAnimation", "CAAnimation", "withAnimation(",
            ".animation(", "NSViewAnimation", "CATransition"
        ]
        let translucencyAPIs = ["NSVisualEffectView", ".ultraThinMaterial", ".regularMaterial", "blendingMode"]

        var motionUses: [String] = []
        var translucencyUses: [String] = []
        var accommodations = 0

        for (name, text) in try productionSources() {
            for api in motionAPIs where text.contains(api) { motionUses.append("\(name): \(api)") }
            for api in translucencyAPIs where text.contains(api) { translucencyUses.append("\(name): \(api)") }
            if text.contains("accessibilityDisplayShouldReduceMotion")
                || text.contains("accessibilityDisplayShouldReduceTransparency") {
                accommodations += 1
            }
        }

        if motionUses.isEmpty && translucencyUses.isEmpty {
            #expect(accommodations == 0, "an accommodation exists with nothing to accommodate")
        } else {
            #expect(
                accommodations > 0,
                """
                production uses motion or translucency with no Reduce Motion / Reduce Transparency \
                accommodation anywhere.
                motion: \(motionUses)
                translucency: \(translucencyUses)
                """
            )
        }
    }

    // Validates: REQ-140 — the deferred text-scaling boundary is honest: production adopts no
    // text-scaling API, so no claim is made that the platform preference is honoured.
    @Test func noTextScalingAPIIsAdopted() throws {
        for (name, text) in try productionSources() {
            for api in ["NSFont.preferredFont", "UIFontMetrics", "scaledValue(for:", "accessibilityDisplayShouldIncreaseContrast"] {
                #expect(!text.contains(api), "\(name) adopts \(api); REQ-140 is Deferred precisely because that cannot be verified")
            }
        }
    }
}
