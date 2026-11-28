//
//  ProofHygieneTests.swift
//  Markdown EditorTests
//

import Foundation
import Testing
@testable import Markdown_Editor

/// Which tests may read production source, and why.
///
/// // Verifies: `CLAUDE.md` §3 — "Grepping source is legitimate only to prove an *absence*, and
/// such a check should verify its own detector works."
///
/// COR-90 found six tests asserting the **presence** of a string in a production file. Those
/// assert spelling rather than behaviour: they redden on a rename or a line wrap that changes
/// nothing, and stay green when the behaviour they name is broken by any means the needle does
/// not mention. One of them checked that `ContentView.swift` contained a specific expression,
/// six lines below an assertion that already proved the behaviour.
///
/// This is deliberately an allowlist of *files* rather than a scanner for assertion shapes.
/// A scanner would have to parse Swift to tell `contains` used for an absence proof from
/// `contains` used for a presence proof, and a gate that can be defeated by renaming a local
/// variable is the kind of proxy ADR 0001 is about. An allowlist cannot be defeated
/// accidentally: reading production source from a new test file fails here until someone says
/// what absence it proves.
struct ProofHygieneTests {

    /// Test files permitted to read production source, each with the absence it proves.
    static let allowed: [String: String] = [
        "TestHelpers.swift":
            "provides productionSourceFiles()/productionSourceText() for the readers below",
        "DisplayPreferencePolicyTests.swift":
            "no colour is constructed outside EditorColorCatalog (REQ-141)",
        "PrivacyBoundaryTests.swift":
            "no analytics/authentication framework and no entitlements file (REQ-031)",
        "AcceptedEditTransactionTests.swift":
            "displaced architecture routes stay deleted (REQ-057, ARC-002/003/013)",
        "ImagePlacementTests.swift":
            "no production file raises an alert outside presentAlert (ARC-017)",
        "PerformanceCorpusTests.swift":
            "the benchmark driver never inspects accessibility or synthetic UI (REQ-128)",
        "DocumentLifecycleContractTests.swift":
            "there is exactly one document/undo/source owner and no shadow subsystem (REQ-013/015/019)",
        "VisualReviewFixtureTests.swift":
            "the inventory of production test hooks is closed and each entry is justified",
        "PerformanceBudgetTests.swift":
            "production never calls ensureLayout(); layout is measured, never provoked (REQ-116)",
        "EditorToolbarConstructionTests.swift":
            "no formatting control row survives in document content (REQ-058)",
        "LaunchSurfaceTests.swift":
            "no undeclared MARKDOWN_EDITOR_* environment variable is read (REQ-144)",
        "MarkdownParserTests.swift":
            "the pinned cmark-gfm licence is present with its provenance (not a source grep)",
    ]

    private static func testSourceFiles() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
    }

    /// Reading production source is an exception, and the set of exceptions is closed.
    @Test func onlyAllowlistedTestsReadProductionSource() throws {
        let files = try Self.testSourceFiles()
        // The detector proves itself: this file is in the directory it is scanning, so an empty
        // or unreadable result is a broken detector rather than a clean repository.
        #expect(
            files.contains { $0.lastPathComponent == "ProofHygieneTests.swift" },
            "the detector did not find its own file and would pass vacuously"
        )

        var readers: [String] = []
        for file in files {
            // The detector's own file necessarily contains the needles it searches for.
            guard file.lastPathComponent != "ProofHygieneTests.swift" else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            let readsProductionSource = text.contains("appendingPathComponent(\"Markdown Editor/")
                || text.contains("appendingPathComponent(\"Markdown Editor\")")
                || text.contains("productionSourceText()")
                || text.contains("productionSourceFiles()")
            if readsProductionSource { readers.append(file.lastPathComponent) }
        }

        // The detector recognises a known reader.
        #expect(
            readers.contains("DisplayPreferencePolicyTests.swift"),
            "the detector missed a known production-source reader and would pass vacuously"
        )

        let undeclared = Set(readers).subtracting(Self.allowed.keys)
        #expect(
            undeclared.isEmpty,
            """
            these tests read production source without declaring the absence they prove: \
            \(undeclared.sorted()). Source inspection proves absences only — assert behaviour \
            instead, or add an entry to ProofHygieneTests.allowed saying what cannot be there.
            """
        )

        // A stale allowlist is its own defect: an entry naming a file that no longer reads
        // production source invites the next reader to inherit an unexamined exemption.
        let stale = Set(Self.allowed.keys).subtracting(readers)
        #expect(stale.isEmpty, "allowlist entries that no longer read production source: \(stale.sorted())")
    }

    /// Every allowlist entry states a reason, so the exemption is reviewable.
    @Test func everyAllowlistEntryStatesWhatItProves() {
        #expect(!Self.allowed.isEmpty)
        for (file, reason) in Self.allowed {
            #expect(reason.count > 20, "\(file) has no meaningful justification")
        }
    }
}
