//
//  VisualReviewFixtureTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

/// The REQ-104 visual-review fixture must be able to *discriminate*.
///
/// // Verifies: REQ-104/107; ARC-Q13 — the one screenshot taken at every increment close is
/// // mandatory human evidence, and it is only evidence if a reviewer can tell a correct render
/// // from a failure.
///
/// At `88b7bd3` the fixture's `assets/sample.png` was a 64x64 picture of a blank document page —
/// visually identical to the "unrelated generic file icon" ENGINEERING §7 forbids as a missing-
/// image treatment. A reviewer could not tell whether image resolution had worked, and during the
/// August review it was initially misread as a defect. The fixture also carried a single-line
/// fenced block, which hid the COR-27 code-block spacing defect from the same gate.
struct VisualReviewFixtureTests {
    private static func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/Fixtures/\(name)")
    }

    private static func richFixture() throws -> String {
        try String(contentsOf: fixtureURL("smoke-rich.md"), encoding: .utf8)
    }

    // The fenced block must span enough lines for interior spacing to be visible (COR-27).
    // Verifies: REQ-104 — the rich fixture makes fenced-block geometry reviewable.
    @Test func richFixtureFencedBlockSpansMultipleLines() throws {
        let text = try Self.richFixture()
        let fences = text.components(separatedBy: "```")
        try #require(fences.count >= 3, "no fenced block in the rich fixture")
        // fences[1] is the block's info string plus its body.
        let body = fences[1].split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
        let codeLines = body.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(
            codeLines.count >= 3,
            "the fenced block has \(codeLines.count) lines; interior spacing is not reviewable"
        )
    }

    // One resolvable and one deliberately unresolvable reference, so the capture shows a correct
    // render and the labeled placeholder side by side.
    // Verifies: REQ-104 — the rich fixture exercises both image resolution outcomes.
    @Test func richFixtureCarriesResolvableAndUnresolvableImages() throws {
        let text = try Self.richFixture()
        #expect(text.contains("](assets/sample.png)"), "no resolvable image reference")
        #expect(
            text.contains("](assets/does-not-exist.png)"),
            "no unresolvable image reference — the placeholder treatment is never exercised"
        )
        let resolvable = Self.fixtureURL("assets/sample.png")
        let unresolvable = Self.fixtureURL("assets/does-not-exist.png")
        #expect(FileManager.default.fileExists(atPath: resolvable.path))
        #expect(!FileManager.default.fileExists(atPath: unresolvable.path))
    }

    // The resolvable image must not itself look like the failure mode. A document-page icon is
    // mostly one flat colour with thin dark edges; this asserts real chromatic variety instead.
    // Verifies: REQ-104 — the fixture image discriminates real content from a placeholder.
    @Test func fixtureImageIsVisuallyDistinctFromAPlaceholder() throws {
        let url = Self.fixtureURL("assets/sample.png")
        let image = try #require(NSImage(contentsOf: url), "fixture image did not decode")
        let rep = try #require(
            image.representations.compactMap { $0 as? NSBitmapImageRep }.first
                ?? NSBitmapImageRep(data: try Data(contentsOf: url))
        )
        var distinct = Set<UInt32>()
        var saturated = 0
        var sampled = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
                guard let colour = rep.colorAt(x: x, y: y) else { continue }
                sampled += 1
                let r = UInt32(colour.redComponent * 255)
                let g = UInt32(colour.greenComponent * 255)
                let b = UInt32(colour.blueComponent * 255)
                distinct.insert(r << 16 | g << 8 | b)
                let maxC = max(colour.redComponent, colour.greenComponent, colour.blueComponent)
                let minC = min(colour.redComponent, colour.greenComponent, colour.blueComponent)
                if maxC - minC > 0.25 { saturated += 1 }
            }
        }
        try #require(sampled > 0)
        #expect(distinct.count >= 2, "fixture image is a single flat colour")
        #expect(
            Double(saturated) / Double(sampled) > 0.2,
            "fixture image is near-greyscale, like the generic file icon it replaced"
        )
    }
}

/// Inventory of production symbols that exist only for tests or verification runs.
///
/// // COR-30: eleven `…ForTesting` members and the smoke-run affordances ship in the product
/// // binary. They are internal and small, and introducing a module boundary for them is not
/// // worth it — but they should be counted and justified rather than accumulating silently.
/// // This fails when the inventory changes, which is the prompt to justify the new entry.
struct ProductionTestHookInventoryTests {
    @Test func productionTestHooksAreInventoried() throws {
        let source = try productionSourceText()
        let hooks = [
            "withParseLockForTesting",       // serialises cmark's process-wide critical section
            "notificationCenterForTesting",  // injects a center so tests do not use .default
            "applyHistoryPatchForTesting",   // drives undo/redo without an AppKit undo manager
            "installTextForTesting",         // seeds canonical source without a file
            "phaseForTesting",               // reads image-placement phase
            "documentLocationGenerationForTesting",
            "prepareUntitledPlacementForTesting",
            "installProjectionForTesting",   // seeds a projection; validates through the oracle
            "clearProjectionForTesting",
            "installResolvedImagesForTesting",
            "trapsOnReconciliationViolation", // lets a suite provoke ARC-015 without trapping
            "recordForTesting",               // feeds FrameObserver's real callback without a display link
            "bumpGenerationWithoutCancellationForTesting", // delivers a completed parse as stale
            "currentForTesting",              // observes the active work-ledger frame
            "resetForTesting",                // clears test-owned ledger state between cases
        ]
        for hook in hooks {
            #expect(source.contains(hook), "inventoried hook \(hook) no longer exists")
        }
        // Any `ForTesting` symbol not in the list above is new and needs justifying here.
        var found = Set<String>()
        var searchRange = source.startIndex..<source.endIndex
        while let match = source.range(of: #"\w+ForTesting"#, options: .regularExpression, range: searchRange) {
            found.insert(String(source[match]))
            searchRange = match.upperBound..<source.endIndex
        }
        let undeclared = found.subtracting(hooks)
        #expect(undeclared.isEmpty, "undeclared production test hooks: \(undeclared.sorted())")
    }
}
