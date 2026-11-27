//
//  AuthoritativeRebuildCountTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

/// How many whole-document rebuilds one semantic command performs.
///
/// // Verifies: REQ-143; ARC-Q06 — a command reconciles the document once, not once per validator.
///
/// COR-89 found three per command: the planner's, plus `validateAcceptedEdit` reached twice —
/// from `EditorTransactionKernel.reduce` and again from
/// `MarkdownDocument.commitEditorTransaction` — each rebuilding the whole document to compare
/// against the snapshot the planner had just produced. On `tableDense` that was roughly 27 ms
/// three times over, on the main actor, while the user waited.
///
/// The validations are COR-70's owner-boundary proof and are **not** removed; the builder
/// memoises its last result, which is indistinguishable from recomputing a pure function.
/// `ownerRejectsForgedStructuralAndCheckboxTransactions` still passes, and still would if the
/// memo were deleted — that is the point.
@MainActor
struct AuthoritativeRebuildCountTests {

    @MainActor
    private final class Fixture {
        let document = MarkdownDocument()
        let session = EditorSession()
        let router = EditorActionRouter()
        let controller = EditorCommandController()
        static let lead = "Measured paragraph."

        init() {
            document.installTextForTesting(
                Self.lead + "\n\nAlpha bravo charlie.\n\n- one\n- two\n\nDelta echo foxtrot.\n"
            )
            session.attach(document: document)
            session.setMode(.wysiwyg)
            if let tree = MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion).get() {
                let index = MarkdownSourceIndex(source: document.text, sourceVersion: document.sourceVersion)
                session.installProjectionForTesting(
                    MarkdownProjectionModel.build(tree: tree, index: index),
                    tree: tree
                )
            }
            controller.bind(document: document, session: session, actionRouter: router, window: nil)
        }

        func selectLead() {
            guard let presentation = session.presentation else { return }
            session.updateWYSIWYGModeState {
                $0.selection = ProjectionSelection(
                    utf16: NSRange(location: 0, length: (Self.lead as NSString).length),
                    revision: presentation.projectionRevision
                )
            }
        }

        func tearDown() { session.detach() }
    }

    /// The count itself, measured through the production route by the work ledger's own parse
    /// counter — the instrument that existed all along and that nothing had ever read.
    ///
    /// // Fails at 3 against the pre-COR-89 build.
    /// // The counters are global, and this test runs no `await` between resetting them and
    /// reading them, so no other `@MainActor` suite can interleave. An off-main suite
    /// (`SpecCorpusTests` parses 1,324 examples) can still inflate the parse counter — but
    /// inflation makes this test **fail**, never pass falsely, so the race is in the safe
    /// direction. The mechanism itself is proved deterministically below, against memos this
    /// suite owns.
    @Test func oneCommandPerformsOneAuthoritativeRebuild() {
        let fixture = Fixture()
        defer { fixture.tearDown() }

        // Warm-up: the first command on a fresh session also reconciles the initial projection.
        fixture.selectLead()
        #expect(fixture.controller.perform(.bold) == .accepted)

        AuthoritativePresentationBuilder.resetMemoForTesting()
        fixture.selectLead()
        #expect(fixture.controller.perform(.bold) == .accepted)

        let builds = AuthoritativePresentationBuilder.performedBuildCountForTesting
        #expect(
            builds == 1,
            """
            one command performed \(builds) whole-document rebuilds. Before COR-89 this was 3: \
            the planner's, plus validateAcceptedEdit reached from both the kernel reduction and \
            the document commit.
            """
        )
    }

    /// // Verifies: REQ-143 — the same new text is parsed once, not once per validator.
    ///
    /// `SemanticEditPlanners.replaceValidated` parses the candidate text to check a postcondition,
    /// and `AuthoritativePresentationBuilder.build` parses the same text again to produce the
    /// snapshot. Fails at 2 against the pre-COR-89 build.
    ///
    /// Counted on the session's own parse memo, after the warm-up command's background
    /// reconciliation has landed. It read a process-wide counter, which every concurrent suite's
    /// parses raised: CI 46009037920 counted 3.
    @Test func oneCommandParsesItsCandidateTextOnce() async {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let trace = InMemoryEditorTrace()
        fixture.document.trace = trace
        fixture.selectLead()
        #expect(fixture.controller.perform(.bold) == .accepted)
        await Self.settle(fixture, trace)

        AuthoritativePresentationBuilder.resetMemoForTesting()
        let memo = fixture.session.intentRecorder.parseMemo
        memo.release()
        let before = memo.performedParseCount
        fixture.selectLead()
        #expect(fixture.controller.perform(.bold) == .accepted)

        let parses = memo.performedParseCount - before
        #expect(parses == 1, "one command performed \(parses) cmark parses of its candidate text")
    }

    /// Each session parses through its own memo, so another document's parse cannot evict a
    /// command's entry between its postcondition parse and its snapshot build.
    @Test func aSessionsParsesUseItsOwnMemo() async {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let trace = InMemoryEditorTrace()
        fixture.document.trace = trace
        fixture.selectLead()
        #expect(fixture.controller.perform(.bold) == .accepted)
        await Self.settle(fixture, trace)

        #expect(fixture.session.intentRecorder.parseMemo.performedParseCount > 0, "the command's parses went to another memo")
        let other = Fixture()
        defer { other.tearDown() }
        #expect(other.session.intentRecorder.parseMemo !== fixture.session.intentRecorder.parseMemo)
        #expect(other.session.intentRecorder.parseMemo !== MarkdownParser.ParseMemo.shared)
    }

    /// Return and Backspace, planned against a tree older than the text, parse the text through
    /// the session's memo, which holds what the reconciliation just parsed. Without their intent
    /// the parse went to the process's shared memo and missed.
    @Test func blockBoundaryPlanningParsesThroughTheSessionsMemo() {
        let snapshot = SourceSnapshot(text: "First paragraph.\n\nSecond.\n", sourceVersion: 4, locationGeneration: 0, fileURL: nil)
        let recorder = IntentRecorder()
        let intent = recorder.begin(.acceptedEdit)
        defer { recorder.finish(intent) }
        let context = BlockBoundaryPlanner.Context(snapshot: snapshot, tree: nil, intent: intent)
        #expect(context != nil)
        #expect(recorder.parseMemo.performedParseCount == 1, "the planner's parse did not go through the session's memo")
    }

    /// Waits until the document's current revision has been reconciled, if a reconciliation was
    /// scheduled for it, so its background parse cannot land inside a measurement.
    private static func settle(_ fixture: Fixture, _ trace: InMemoryEditorTrace) async {
        let revision = fixture.document.sourceVersion
        func scheduled() -> Bool {
            !trace.eventsMatching {
                if case .reconciliationScheduled(let scheduled, _) = $0 { return scheduled == revision }
                return false
            }.isEmpty
        }
        func landed() -> Bool {
            !trace.eventsMatching {
                switch $0 {
                case .reconciliationApplied(_, let applied, _, _): return applied == revision
                case .reconciliationDiscarded(let discarded, _): return discarded == revision
                default: return false
                }
            }.isEmpty
        }
        for _ in 0..<1_000 where scheduled() && !landed() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// A parse memo hit must equal a fresh parse, which is what makes memoising it invisible.
    @Test func aParseMemoHitEqualsAFreshParse() {
        let source = "# Heading\n\n- a\n- b\n\n| x | y |\n|---|---|\n| 1 | 2 |\n"
        // Its own memo, so no concurrently-running suite can evict the entry under it.
        let memo = MarkdownParser.ParseMemo()
        let fresh = try? MarkdownParser.parse(source, sourceVersion: 3, memo: memo).get()
        let hit = try? MarkdownParser.parse(source, sourceVersion: 3, memo: memo).get()
        let cold = MarkdownParser.ParseMemo()
        let rebuilt = try? MarkdownParser.parse(source, sourceVersion: 3, memo: cold).get()
        #expect(fresh != nil)
        #expect(hit == fresh)
        #expect(rebuilt == fresh, "the parser is not a pure function of its key; memoising it is unsound")
        #expect(memo.performedParseCount == 1, "the second call re-parsed instead of hitting")

        // A different version of identical text is a different key, so it is parsed again.
        let versions = MarkdownParser.ParseMemo()
        _ = MarkdownParser.parse(source, sourceVersion: 1, memo: versions)
        _ = MarkdownParser.parse(source, sourceVersion: 2, memo: versions)
        #expect(versions.performedParseCount == 2)
    }

    /// // Verifies: REQ-090 — closing a document releases what the memos retain.
    ///
    /// A one-entry memo is not a leak, but it holds one whole source, tree and snapshot, and a
    /// closed document leaving megabytes resident is the quiet retention the leak smoke run
    /// exists to catch.
    @Test func closingADocumentReleasesTheMemos() throws {
        AuthoritativePresentationBuilder.resetMemoForTesting()
        MarkdownParser.resetParseMemoForTesting()

        let document = MarkdownDocument()
        document.installTextForTesting("# Retained\n\nBody text.\n")
        _ = MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion)
        _ = AuthoritativePresentationBuilder.build(
            source: document.text,
            sourceRevision: document.sourceVersion,
            snapshotID: PresentationSnapshot.ID(value: 99),
            locationGeneration: 0
        )
        let buildsBefore = AuthoritativePresentationBuilder.performedBuildCountForTesting
        let parsesBefore = MarkdownParser.performedParseCountForTesting

        document.close()

        // A repeat request after close must do the work again, which is observable proof the
        // entries were released rather than merely unreferenced.
        _ = MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion)
        _ = AuthoritativePresentationBuilder.build(
            source: document.text,
            sourceRevision: document.sourceVersion,
            snapshotID: PresentationSnapshot.ID(value: 99),
            locationGeneration: 0
        )
        #expect(
            AuthoritativePresentationBuilder.performedBuildCountForTesting > buildsBefore,
            "the snapshot memo survived close()"
        )
        #expect(
            MarkdownParser.performedParseCountForTesting > parsesBefore,
            "the parse memo survived close()"
        )
    }

    /// A memo hit must not swallow cancellation.
    ///
    /// // Verifies: REQ-085 — `parse` promises `.failure(.cancelled)` to a cancelled caller. When
    /// the memo was consulted first, a cancelled caller whose answer happened to be stored got
    /// `.success` instead. Harmless in the one production caller, which re-checks
    /// `Task.isCancelled` immediately afterwards, but a memo that changes an observable contract
    /// is not a memo — it is a behaviour change wearing one.
    @Test func aCancelledParseIsCancelledEvenOnAMemoHit() {
        let source = "# Cancel me\n\nBody.\n"
        let memo = MarkdownParser.ParseMemo()

        // Populate this memo, and prove it is populated — otherwise the assertion below could
        // pass because the call *missed* and hit the parser's own cancellation guard, which is
        // exactly how the first version of this test passed while proving nothing.
        #expect((try? MarkdownParser.parse(source, sourceVersion: 1, memo: memo).get()) != nil)
        #expect(memo.tree(source: source, sourceVersion: 1) != nil, "the memo is not populated")

        let cancelled = MarkdownParser.parse(
            source, sourceVersion: 1, isCancelled: { true }, memo: memo
        )
        guard case .failure(let reason) = cancelled else {
            Issue.record("a cancelled parse returned success from the memo")
            return
        }
        #expect(reason == .cancelled)

        // The memo is otherwise intact: an uncancelled caller still gets the stored tree.
        let before = memo.performedParseCount
        #expect((try? MarkdownParser.parse(source, sourceVersion: 1, memo: memo).get()) != nil)
        #expect(memo.performedParseCount == before)
    }

    /// Memoisation must not survive a change of source, or a stale projection would be served for
    /// a document that has moved on.
    @Test func adifferentSourceIsRebuiltRatherThanServedFromTheMemo() {
        AuthoritativePresentationBuilder.resetMemoForTesting()
        let first = AuthoritativePresentationBuilder.build(
            source: "# One\n",
            sourceRevision: 1,
            snapshotID: PresentationSnapshot.ID(value: 1),
            locationGeneration: 0
        )
        let second = AuthoritativePresentationBuilder.build(
            source: "# Two\n",
            sourceRevision: 2,
            snapshotID: PresentationSnapshot.ID(value: 2),
            locationGeneration: 0
        )
        #expect(first?.renderedString != second?.renderedString)
        #expect(second?.renderedString.contains("Two") == true)

        // Re-requesting the first key rebuilds it, because the memo holds one entry.
        let again = AuthoritativePresentationBuilder.build(
            source: "# One\n",
            sourceRevision: 1,
            snapshotID: PresentationSnapshot.ID(value: 1),
            locationGeneration: 0
        )
        #expect(again == first, "a rebuild of the same key disagreed with the original")
    }

    /// A hit must be equal to what a rebuild would produce — the property that makes memoising a
    /// pure function invisible to every caller, including the validator.
    @Test func aMemoHitEqualsAFreshBuild() {
        let source = "# Heading\n\nParagraph with **strong** text.\n\n- a\n- b\n"
        AuthoritativePresentationBuilder.resetMemoForTesting()
        let fresh = AuthoritativePresentationBuilder.build(
            source: source,
            sourceRevision: 7,
            snapshotID: PresentationSnapshot.ID(value: 7),
            locationGeneration: 3
        )
        let hit = AuthoritativePresentationBuilder.build(
            source: source,
            sourceRevision: 7,
            snapshotID: PresentationSnapshot.ID(value: 7),
            locationGeneration: 3
        )
        AuthoritativePresentationBuilder.resetMemoForTesting()
        let rebuilt = AuthoritativePresentationBuilder.build(
            source: source,
            sourceRevision: 7,
            snapshotID: PresentationSnapshot.ID(value: 7),
            locationGeneration: 3
        )
        #expect(fresh != nil)
        #expect(hit == fresh)
        #expect(rebuilt == fresh, "the builder is not a pure function of its key; memoising it is unsound")
    }

    /// Every component of the key must participate, or a snapshot could be served under an
    /// identity it was not built for.
    @Test func everyKeyComponentDistinguishesTheMemo() {
        let source = "# K\n"
        func build(revision: UInt64, id: UInt64, generation: UInt64) -> PresentationSnapshot? {
            AuthoritativePresentationBuilder.build(
                source: source,
                sourceRevision: revision,
                snapshotID: PresentationSnapshot.ID(value: id),
                locationGeneration: generation
            )
        }
        AuthoritativePresentationBuilder.resetMemoForTesting()
        let base = build(revision: 1, id: 1, generation: 1)
        #expect(build(revision: 2, id: 1, generation: 1)?.sourceRevision.value == 2)
        #expect(build(revision: 1, id: 2, generation: 1)?.id.value == 2)
        #expect(build(revision: 1, id: 1, generation: 2)?.locationGeneration == 2)
        #expect(base?.sourceRevision.value == 1)
    }
}
