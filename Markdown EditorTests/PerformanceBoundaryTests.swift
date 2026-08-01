//
//  PerformanceBoundaryTests.swift
//  Markdown EditorTests
//
//  COR-20 proof that `.nativeInputCallback` measures the complete native callback — semantic
//  planning, source commit, attributed patch, attachment update, and selection restoration —
//  rather than only the part that was already fast.
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

@MainActor
struct PerformanceBoundaryTests {
    /// Injects a measurable stall inside `NSTextStorage.replaceCharacters`. If the sample were
    /// taken before TextKit application — the defect this test exists to catch — the recorded
    /// duration would not contain the stall.
    // Verifies: REQ-090/103/109; ARC-020
    @Test func nativeInputCallbackSampleEnclosesStorageApplication() throws {
        let stall: TimeInterval = 0.05
        // Two paragraphs, so a bounded patch is visibly smaller than the document.
        let harness = try EditorHarness(source: "Hello world.\n\nSecond paragraph.\n")
        harness.storage.mutationDelay = stall

        harness.typeCharacter("!", at: NSRange(location: 12, length: 0))

        let summary = try #require(
            harness.session.drainPerformanceSummaries().first { $0.metric == .nativeInputCallback }
        )
        #expect(summary.count == 1)
        let recordedSeconds = Double(summary.max) / 1_000_000_000
        #expect(
            recordedSeconds >= stall,
            "callback sample \(recordedSeconds)s excludes the \(stall)s storage stall"
        )
        // The stall was inside a bounded patch, not a document rebuild.
        #expect(harness.storage.fullReplacements == 0)
        #expect(harness.storage.characterReplacements.count == 1)
        let patched = try #require(harness.storage.characterReplacements.first)
        #expect(patched.length < (harness.session.presentation?.renderedString as NSString?)?.length ?? 0)
        #expect(harness.document.text == "Hello world.!\n\nSecond paragraph.\n")
    }

    // Verifies: REQ-103 — ordinary edits feed the sampler and emit no per-keystroke record.
    @Test func ordinaryEditsProduceAggregatesOnlyAndNoPerKeystrokeRecord() throws {
        let trace = InMemoryEditorTrace()
        let harness = try EditorHarness(source: "Hello world.\n", trace: trace)

        for offset in 0..<5 {
            harness.typeCharacter("x", at: NSRange(location: 12 + offset, length: 0))
        }

        let summary = try #require(
            harness.session.drainPerformanceSummaries().first { $0.metric == .nativeInputCallback }
        )
        #expect(summary.count == 5)
        // No performance record per keystroke: aggregates are emitted by the periodic flush only.
        let perKeystroke = trace.eventsMatching {
            if case .performanceSummary = $0 { return true }
            return false
        }
        #expect(perKeystroke.isEmpty)
        #expect(harness.document.text == "Hello world.xxxxx\n")
    }

    // Verifies: REQ-109 — storage drift is resynchronized *and recorded*, never silently.
    @Test func driftedStorageIsResynchronizedAndRecorded() throws {
        let trace = InMemoryEditorTrace()
        let harness = try EditorHarness(source: "Hello world.\n", trace: trace)

        // Diverge applied storage from the snapshot the next keystroke targets.
        harness.storage.replaceCharacters(in: NSRange(location: 0, length: 5), with: "HELLO")
        harness.typeCharacter("!", at: NSRange(location: 12, length: 0))

        let recovered = trace.eventsMatching {
            if case .presentationRecovered = $0 { return true }
            return false
        }
        #expect(recovered.count == 1)
        // The drifted keystroke changed no source.
        #expect(harness.document.text == "Hello world.\n")
        #expect(harness.textView.string == harness.session.presentation?.renderedString)
    }

    // Verifies: REQ-109 — a patch whose surrounding text is not identical in both snapshots is
    // refused outright rather than applied on an assumption.
    @Test func patchRefusesWhenSurroundingTextDiffersBetweenSnapshots() throws {
        let fixture = try PatchFixture(source: "hello\n", insert: "!", at: 5)
        // A next snapshot whose *unchanged* region does not match the current one at all.
        let divergent = PresentationSnapshot.make(
            id: PresentationSnapshot.ID(value: 2),
            sourceRevision: SourceRevision(value: 2),
            locationGeneration: 1,
            renderedString: "different!\n",
            runs: [],
            attachments: [],
            tables: [],
            atoms: [.identity(IdentityAtom(
                projection: NSRange(location: 0, length: 11),
                source: NSRange(location: 0, length: 11),
                insertionBefore: 0,
                insertionAfter: 11
            ))],
            sourceUTF16Count: 11
        )
        let transition = PresentationTransition(
            fromSnapshotID: fixture.current.id,
            nextSnapshot: divergent,
            projectionReplacementRange: NSRange(location: 5, length: 0),
            projectionReplacement: "!",
            selectionAfter: ProjectionSelection(
                utf16: NSRange(location: 6, length: 0),
                revision: divergent.projectionRevision
            )
        )
        let patch = PresentationPatch.make(
            transition: transition,
            current: fixture.current,
            buildScope: { model, scope in
                AttributedPresentationBuilder.buildScoped(model: model, theme: MarkdownTheme(), scope: scope)
            }
        )
        #expect(patch == nil)
    }

    /// A real document, session, and WYSIWYG coordinator over spy-backed storage.
    @MainActor
    final class EditorHarness {
        let document = MarkdownDocument()
        let session = EditorSession()
        let coordinator: WYSIWYGEditor.Coordinator
        let textView: MarkdownWYSIWYGTextView
        let storage: SpyTextStorage

        init(source: String, trace: (any EditorTraceSink)? = nil) throws {
            if let trace { document.trace = trace }
            document.installTextForTesting(source)
            session.attach(document: document)
            session.setMode(.wysiwyg)

            let index = MarkdownSourceIndex(source: source, sourceVersion: document.sourceVersion)
            let tree = try #require(
                MarkdownParser.parse(source, sourceVersion: document.sourceVersion).get()
            )
            let model = MarkdownProjectionModel.build(tree: tree, index: index)
            session.installProjectionForTesting(model, tree: tree)

            (textView, storage) = makeSpyBackedTextView()
            coordinator = WYSIWYGEditor.Coordinator(
                document: document,
                session: session,
                placementController: ImagePlacementController()
            )
            coordinator.textView = textView
            coordinator.applyProjectionIfNeeded(force: true)
            storage.resetSpy()
        }

        /// Drives the real native delegate callback, the one whose latency the budget describes.
        func typeCharacter(_ text: String, at range: NSRange) {
            session.updateOrigin.with(.nativeUserInput) {
                _ = coordinator.textView(
                    textView,
                    shouldChangeTextIn: range,
                    replacementString: text
                )
            }
        }

        deinit {
            MainActor.assumeIsolated { session.detach() }
        }
    }
}
