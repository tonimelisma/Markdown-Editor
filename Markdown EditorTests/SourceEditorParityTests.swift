//
//  SourceEditorParityTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

@MainActor
struct SourceEditorParityTests {
    // Verifies: REQ-045 — ordinary source edits reset and restyle only their changed line.
    @Test func sourceHighlightAppliesOnlyToTheChangedWindow() async throws {
        let source = (0..<80).map { "ordinary source line \($0) with enough text to measure" }.joined(separator: "\n") + "\n"
        let fixture = try makeFixture(source: source)
        let highlighter = MarkdownHighlighter()
        let initialTokens = try await highlighter.tokens(for: source)
        fixture.coordinator.apply(initialTokens, expectedVersion: 0, expectedText: source)

        let editLocation = (source as NSString).range(of: "ordinary source line 40").location
        let edited = NSMutableString(string: source)
        edited.replaceCharacters(in: NSRange(location: editLocation, length: 1), with: "O")
        fixture.storage.resetSpy()
        let editedText = edited as String
        fixture.storage.replaceCharacters(in: NSRange(location: editLocation, length: 1), with: "O")
        fixture.storage.resetSpy()
        let tokens = try await highlighter.tokens(for: editedText)
        fixture.coordinator.apply(
            tokens,
            expectedVersion: 0,
            expectedText: editedText,
            editedRange: NSRange(location: editLocation, length: 1)
        )

        let writtenCharacters = fixture.storage.attributeReplacements.reduce(0) { $0 + $1.length }
        #expect(writtenCharacters < Int(Double((editedText as NSString).length) * 0.05))
        #expect(fixture.storage.string == editedText)
    }

    // Verifies: REQ-045; ARC-020 — the source styling application is a sampled main-actor boundary.
    @Test func sourceHighlightApplicationIsRecorded() async throws {
        let source = "# Heading\nplain text\n"
        let fixture = try makeFixture(source: source)
        let tokens = try await MarkdownHighlighter().tokens(for: source)
        fixture.coordinator.apply(tokens, expectedVersion: 0, expectedText: source)

        let summaries = fixture.session.drainPerformanceSummaries()
        #expect(summaries.contains { $0.metric == .sourceHighlightApplication && $0.count == 1 })
    }

    // Verifies: REQ-045 — source highlighting remains live across every approved corpus shape.
    @Test(arguments: PerformanceCorpus.allCases)
    func sourceHighlightEnumeratesEveryPerformanceCorpus(_ corpus: PerformanceCorpus) async throws {
        let source = corpus.source(utf16Target: 20_000)
        let fixture = try makeFixture(source: source)
        fixture.coordinator.apply(
            try await MarkdownHighlighter().tokens(for: source),
            expectedVersion: 0,
            expectedText: source
        )
        #expect(fixture.storage.string == source)
        #expect(fixture.session.drainPerformanceSummaries().contains {
            $0.metric == .sourceHighlightApplication
        })
    }

    // Verifies: REQ-045 — changing fence parity widens the pass so content below a new opener is
    // not left with stale non-code attributes, and the widening is visible in diagnostics.
    @Test func typingAFenceWidensTheStyleWindow() async throws {
        let source = "title\ncode *literal*\nafter\n"
        let fixture = try makeFixture(source: source)
        let highlighter = MarkdownHighlighter()
        fixture.coordinator.apply(try await highlighter.tokens(for: source), expectedVersion: 0, expectedText: source)

        let editedText = "title\n```\ncode *literal*\nafter\n"
        fixture.storage.replaceCharacters(in: NSRange(location: 6, length: 0), with: "```\n")
        fixture.storage.resetSpy()
        fixture.coordinator.apply(
            try await highlighter.tokens(for: editedText),
            expectedVersion: 0,
            expectedText: editedText,
            editedRange: NSRange(location: 6, length: 4)
        )

        let full = NSRange(location: 0, length: (editedText as NSString).length)
        #expect(fixture.storage.attributeReplacements.contains(full))
        #expect(fixture.trace.events.contains(.sourceHighlightWidened(reason: .fenceParity)))
        let codeLocation = (editedText as NSString).range(of: "code").location
        let codeFont = fixture.storage.attributes(at: codeLocation, effectiveRange: nil)[.font] as? NSFont
        #expect(codeFont?.isFixedPitch == true)
        #expect(fixture.storage.string == editedText)
    }

    // Verifies: REQ-040/051; ARC-018 — source highlighting never rewrites source bytes, including
    // Unicode and CRLF input.
    @Test func sourceStylingStillLeavesTheStringUnchanged() async throws {
        let source = "# Café 🐙\r\n**literal** and `code`\r\n"
        let fixture = try makeFixture(source: source)
        fixture.coordinator.apply(
            try await MarkdownHighlighter().tokens(for: source),
            expectedVersion: 0,
            expectedText: source
        )
        #expect(fixture.storage.string == source)
    }

    private struct Fixture {
        let coordinator: SourceEditor.Coordinator
        let storage: SpyTextStorage
        let session: EditorSession
        let trace: InMemoryEditorTrace
    }

    private func makeFixture(source: String) throws -> Fixture {
        let document = MarkdownDocument()
        document.installTextForTesting(source)
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let session = EditorSession(performanceSamplerCoordinator: DiagnosticRunCoordinator())
        session.attach(document: document)

        let placement = ImagePlacementController()
        placement.attach(actions: document)
        placement.trace = trace
        let coordinator = SourceEditor.Coordinator(
            document: document,
            placementController: placement,
            session: session
        )
        let storage = SpyTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        let textView = MarkdownSourceTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: source)
        storage.resetSpy()
        textView.delegate = coordinator
        coordinator.textView = textView
    return Fixture(coordinator: coordinator, storage: storage, session: session, trace: trace)
    }
}
