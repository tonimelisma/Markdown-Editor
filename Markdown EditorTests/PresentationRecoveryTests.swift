//
//  PresentationRecoveryTests.swift
//  Markdown EditorTests
//
//  COR-71: when an authoritative parse lands, a provisional WYSIWYG snapshot of the same
//  revision is checked against it, and a disagreement is a recorded fault. These tests drive the
//  real session and parse coordinator through a complete reconciliation, which the synchronous
//  suites around them never wait for.
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

@MainActor
@Suite(.serialized)
struct PresentationRecoveryTests {

    private func recoveries(_ trace: InMemoryEditorTrace) -> [EditorTraceEvent] {
        trace.eventsMatching {
            if case .presentationRecovered = $0 { return true }
            return false
        }
    }

    private func reconciliations(_ trace: InMemoryEditorTrace, revision: UInt64) -> Int {
        trace.eventsMatching {
            if case .reconciliationApplied(_, let applied, _, _) = $0 { return applied == revision }
            return false
        }.count
    }

    /// Waits for `count` reconciliations of `revision` to have been applied, bounded in
    /// main-actor turns rather than by the clock, so a busy parallel suite stretches the wait
    /// instead of failing it.
    private func awaitReconciliations(
        _ trace: InMemoryEditorTrace, revision: UInt64, count: Int, maxPolls: Int = 2_000
    ) async {
        var polls = 0
        while reconciliations(trace, revision: revision) < count, polls < maxPolls {
            polls += 1
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // Verifies: REQ-109 — a second authoritative parse of an unchanged revision is not a fault.
    // In the smoke run of repeat-smoke 45925262536 an edit's own parse installed revision 3, and
    // then the deferred document-change parse installed it again; the check compared snapshot IDs,
    // which always differ, and recorded `patchUnprovable` against an authoritative snapshot.
    @Test func reparsingAnInstalledRevisionIsNotARecovery() async throws {
        let trace = InMemoryEditorTrace()
        let document = MarkdownDocument()
        document.trace = trace
        document.installTextForTesting("Hello **world**.\n")
        let session = EditorSession()
        session.attach(document: document)
        defer { session.detach() }
        session.setMode(.wysiwyg)
        let revision = document.sourceVersion
        await awaitReconciliations(trace, revision: revision, count: 1)
        try #require(reconciliations(trace, revision: revision) == 1, "the opening parse never landed")

        session.scheduleParse()
        await awaitReconciliations(trace, revision: revision, count: 2)

        #expect(reconciliations(trace, revision: revision) == 2, "the second parse never landed")
        #expect(recoveries(trace).isEmpty, "a re-parse of an unchanged revision was recorded as a recovery: \(recoveries(trace))")
        #expect(session.presentation?.sourceRevision.value == revision)
    }

    // Verifies: REQ-109 — an ordinary WYSIWYG keystroke is reconciled without a recovery. Its
    // provisional snapshot and the authoritative one describe the same text, so the authority
    // replaces it silently and the selection survives.
    @Test func aWYSIWYGKeystrokeIsReconciledWithoutRecovery() async throws {
        let trace = InMemoryEditorTrace()
        let harness = try PerformanceBoundaryTests.EditorHarness(source: "Hello world.\n", trace: trace)
        let opened = harness.document.sourceVersion
        await awaitReconciliations(trace, revision: opened, count: 1)

        harness.typeCharacter("!", at: NSRange(location: 11, length: 0))
        let typed = harness.document.sourceVersion
        try #require(typed != opened, "the keystroke did not commit")
        await awaitReconciliations(trace, revision: typed, count: 1)

        #expect(reconciliations(trace, revision: typed) >= 1, "the keystroke's parse never landed")
        #expect(recoveries(trace).isEmpty, "an ordinary keystroke was recorded as a recovery: \(recoveries(trace))")
        #expect(harness.document.text == "Hello world!.\n")
        #expect(harness.session.wysiwygModeState.selection != nil, "the reconciliation dropped the caret")
    }

    // Verifies: REQ-085 — a semantic edit's revision is parsed once. `perform` schedules the parse
    // itself; the same commit's `objectWillChange` also queued a deferred document-change parse,
    // so every source-planned edit was parsed twice (the release timeline of Release 45922511341
    // shows `parseStarted` for revision 3 twice), and the second could land after the first had
    // installed — the interleaving behind the COR-71 fault above.
    @Test func aSemanticEditIsParsedOnce() async throws {
        let trace = InMemoryEditorTrace()
        let document = MarkdownDocument()
        document.trace = trace
        document.installTextForTesting("Hello.\n")
        let session = EditorSession()
        session.attach(document: document)
        defer { session.detach() }
        await awaitReconciliations(trace, revision: document.sourceVersion, count: 1)

        session.setMode(.source)
        let caret = SourceSelection(utf16: NSRange(location: 0, length: 0))
        session.updateSourceModeState { $0.selection = caret }
        session.perform(
            .insertText("x"),
            selection: .source(caret),
            expectedSourceRevision: SourceRevision(value: document.sourceVersion)
        )
        let edited = document.sourceVersion
        try #require(document.text == "xHello.\n", "the edit did not commit")
        await awaitReconciliations(trace, revision: edited, count: 1)
        // Long enough for a deferred second parse to start: it waits only one yield.
        for _ in 0..<100 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }

        let parses = trace.eventsMatching {
            if case .parseStarted(let version, _) = $0 { return version == edited }
            return false
        }.count
        #expect(parses == 1, "revision \(edited) was parsed \(parses) times")
    }

    // Verifies: REQ-109 — the check still catches what it exists for. A provisional snapshot whose
    // content disagrees with the authoritative parse of its revision is recorded, exactly once,
    // and replaced. Without this, a fix to the two tests above could pass by making the check
    // vacuous.
    @Test func aProvisionalThatDisagreesWithTheParseIsRecorded() async throws {
        let trace = InMemoryEditorTrace()
        let document = MarkdownDocument()
        document.trace = trace
        document.installTextForTesting("Hello **world**.\n")
        let session = EditorSession()
        session.attach(document: document)
        defer { session.detach() }
        session.setMode(.wysiwyg)
        let revision = document.sourceVersion
        await awaitReconciliations(trace, revision: revision, count: 1)
        let authoritative = try #require(session.presentation)
        try #require(!authoritative.runs.isEmpty, "the fixture has no styled run to disagree about")

        // The same revision, text and coordinates, but no styling: a local transition that got the
        // presentation wrong.
        let wrong = PresentationSnapshot.make(
            id: session.snapshotIDs.make(),
            sourceRevision: authoritative.sourceRevision,
            locationGeneration: authoritative.locationGeneration,
            renderedString: authoritative.renderedString,
            runs: [],
            attachments: authoritative.attachments,
            tables: authoritative.tables,
            blocks: authoritative.blocks,
            listMarkers: authoritative.listMarkers,
            atoms: authoritative.atoms,
            sourceUTF16Count: authoritative.sourceUTF16Count
        )
        session.installPresentation(wrong, tree: session.authoritativeTree, provisional: true)
        session.scheduleParse()
        await awaitReconciliations(trace, revision: revision, count: 2)

        #expect(recoveries(trace).count == 1, "a provisional snapshot that disagreed with the parse was not recorded: \(recoveries(trace))")
        #expect(session.presentation?.runs.isEmpty == false, "the wrong provisional snapshot was kept")
    }
}
