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

    /// Which of the fields `hasSameContent` compares differ between two snapshots, with both values
    /// for the small ones — the evidence a failed recovery test needs to say what disagreed.
    static func differences(_ a: PresentationSnapshot, _ b: PresentationSnapshot) -> [String] {
        var out: [String] = []
        func check<T: Equatable>(_ name: String, _ x: T, _ y: T) {
            if x != y { out.append("\(name): \(String(describing: x).prefix(600)) ≠ \(String(describing: y).prefix(600))") }
        }
        check("sourceRevision", a.sourceRevision, b.sourceRevision)
        check("locationGeneration", a.locationGeneration, b.locationGeneration)
        check("sourceUTF16Count", a.sourceUTF16Count, b.sourceUTF16Count)
        check("renderedString", a.renderedString, b.renderedString)
        check("runs", a.runs, b.runs)
        check("attachments", a.attachments, b.attachments)
        check("tables", a.tables, b.tables)
        check("blocks", a.blocks, b.blocks)
        check("listMarkers", a.listMarkers, b.listMarkers)
        // Atoms are compared as `hasSameContent` compares them, and the first that differs is
        // shown from both sides: a whole array is too long to read either side in a message.
        let atomsA = ProjectionAtom.coalescingIdentity(a.atoms), atomsB = ProjectionAtom.coalescingIdentity(b.atoms)
        if atomsA != atomsB {
            let index = zip(atomsA, atomsB).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(atomsA.count, atomsB.count)
            let left = atomsA.indices.contains(index) ? String(describing: atomsA[index]) : "none"
            let right = atomsB.indices.contains(index) ? String(describing: atomsB[index]) : "none"
            out.append("atoms (\(atomsA.count) vs \(atomsB.count)) first differ at \(index): \(left) ≠ \(right)")
        }
        return out
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
        await harness.settle()

        harness.typeCharacter("!", at: NSRange(location: 11, length: 0))
        let typed = harness.document.sourceVersion
        try #require(typed != opened, "the keystroke did not commit")
        let provisional = try #require(harness.session.presentation, "the keystroke installed no provisional snapshot")
        await awaitReconciliations(trace, revision: typed, count: 1)

        #expect(reconciliations(trace, revision: typed) >= 1, "the keystroke's parse never landed")
        let differences = harness.session.presentation.map { Self.differences(provisional, $0) } ?? ["no presentation"]
        #expect(recoveries(trace).isEmpty, "an ordinary keystroke was recorded as a recovery: \(recoveries(trace)); provisional vs authoritative: \(differences)")
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

    // Verifies: REQ-109 — identity text split into pieces is the same content as the same text in
    // one piece, and a different mapping is not. An ordinary keystroke's local transition splits
    // identity atoms at the edit where the parser emits one (CI 45939800494).
    @Test func identitySegmentationIsNotADisagreement() {
        func identity(_ projection: NSRange, _ source: NSRange) -> ProjectionAtom {
            .identity(IdentityAtom(
                projection: projection, source: source,
                insertionBefore: source.location, insertionAfter: NSMaxRange(source)
            ))
        }
        let split = [
            identity(NSRange(location: 0, length: 11), NSRange(location: 0, length: 11)),
            identity(NSRange(location: 11, length: 1), NSRange(location: 11, length: 1)),
            identity(NSRange(location: 12, length: 1), NSRange(location: 12, length: 1)),
        ]
        let whole = [identity(NSRange(location: 0, length: 13), NSRange(location: 0, length: 13))]
        #expect(ProjectionAtom.coalescingIdentity(split) == whole)
        #expect(ProjectionAtom.coalescingIdentity(whole) == whole)

        // The same pieces mapped one character further into the source do not continue the first.
        let shifted = [
            identity(NSRange(location: 0, length: 11), NSRange(location: 0, length: 11)),
            identity(NSRange(location: 11, length: 2), NSRange(location: 12, length: 2)),
        ]
        #expect(ProjectionAtom.coalescingIdentity(shifted) != whole)
        #expect(ProjectionAtom.coalescingIdentity(shifted).count == 2)
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

    // Verifies: REQ-109 — a recovery keeps the caret. The recovery cleared the provisional snapshot
    // before installing the authority, and the selection was carried only through the snapshot
    // being replaced, so it was dropped. The caret stayed on screen and every keystroke after it
    // was refused without a trace: agent-drive run 45943545906 typed "Agent " and the document
    // received "A".
    @Test func aRecoveryKeepsTheCaret() async throws {
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
        session.updateWYSIWYGModeState {
            $0.selection = ProjectionSelection(utf16: NSRange(location: 3, length: 0), revision: wrong.projectionRevision)
        }
        session.scheduleParse()
        await awaitReconciliations(trace, revision: revision, count: 2)

        try #require(recoveries(trace).count == 1, "the wrong provisional snapshot was not recovered")
        let installed = try #require(session.presentation)
        let selection = try #require(session.wysiwygModeState.selection, "the recovery dropped the caret")
        #expect(selection.range.utf16 == NSRange(location: 3, length: 0))
        #expect(selection.range.revision == installed.projectionRevision, "the caret belongs to a snapshot that is gone")
    }

    // Verifies: REQ-109 — a keystroke anywhere is reconciled without a recovery. Every caret
    // offset of a document with a heading, a paragraph with a bold run, a list and a quote: a
    // shifted provisional snapshot was wrong exactly where a keystroke meets the start of a run or
    // block, which a test of one interior offset could not see.
    @Test func aKeystrokeAtAnyOffsetIsReconciledWithoutRecovery() async throws {
        let source = "# Title\n\nSome **bold** text.\n\n- item\n\n> quote\n"
        // The rendered length from a harness whose opening parse has landed, as every loop's has.
        let probe = InMemoryEditorTrace()
        let opened = try PerformanceBoundaryTests.EditorHarness(source: source, trace: probe)
        await opened.settle()
        let rendered = opened.session.presentation?.renderedString ?? ""
        try #require((rendered as NSString).length > 20, "the fixture rendered as \(rendered.debugDescription)")
        var recovered: [String] = []
        var refused: [String] = []
        var typedAt = 0
        for offset in 0...(rendered as NSString).length {
            let trace = InMemoryEditorTrace()
            let harness = try PerformanceBoundaryTests.EditorHarness(source: source, trace: trace)
            await harness.settle()
            harness.coordinator.applyProjectionIfNeeded(reason: .newSnapshot)
            let before = harness.document.sourceVersion
            harness.typeCharacter("x", at: NSRange(location: offset, length: 0))
            guard harness.document.sourceVersion != before, let provisional = harness.session.presentation else {
                // Refused here, as on an attachment: no provisional snapshot to check.
                let reasons = trace.eventsMatching {
                    if case .editRefused = $0 { return true }
                    return false
                }
                refused.append("\(offset): \(reasons)")
                continue
            }
            typedAt += 1
            await awaitReconciliations(trace, revision: harness.document.sourceVersion, count: 1)
            if !recoveries(trace).isEmpty {
                let differences = harness.session.presentation.map { Self.differences(provisional, $0) } ?? []
                recovered.append("offset \(offset): \(differences.first ?? "?")")
            }
        }
        #expect(typedAt > 20, "only \(typedAt) offsets accepted a keystroke; refused at \(refused.prefix(6))")
        #expect(recovered.isEmpty, "\(recovered.count) offsets recovered:\n\(recovered.joined(separator: "\n"))")
    }

    // Verifies: REQ-109 — typing a word into a real document is reconciled without a recovery,
    // whether each keystroke's parse lands before the next or the keystrokes outrun them.
    // Agent-drive run 45945859891 typed "Agent " at the start of smoke-rich.md's heading and
    // three of the keystrokes inside the word were recovered, which a plain heading did not show.
    @Test(arguments: [true, false])
    func typingAWordIntoTheRichFixtureIsReconciledWithoutRecovery(waitingForEachParse: Bool) async throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Scripts/Fixtures/smoke-rich.md")
        let source = try String(contentsOf: fixture, encoding: .utf8)
        let trace = InMemoryEditorTrace()
        let harness = try PerformanceBoundaryTests.EditorHarness(source: source, trace: trace)
        await harness.settle()
        harness.coordinator.applyProjectionIfNeeded(reason: .newSnapshot)

        var disagreements: [String] = []
        for (offset, character) in "Agent ".enumerated() {
            let before = recoveries(trace).count
            harness.typeCharacter(String(character), at: NSRange(location: offset, length: 0))
            guard let provisional = harness.session.presentation else { continue }
            let revision = harness.document.sourceVersion
            if waitingForEachParse {
                await awaitReconciliations(trace, revision: revision, count: 1)
                harness.coordinator.applyProjectionIfNeeded(reason: .newSnapshot)
                if recoveries(trace).count > before {
                    let differences = harness.session.presentation.map { Self.differences(provisional, $0) } ?? []
                    disagreements.append("\(character.debugDescription) at \(offset): \(differences.map { $0.prefix(400) })")
                }
            }
        }
        await awaitReconciliations(trace, revision: harness.document.sourceVersion, count: 1)

        #expect(harness.document.text.hasPrefix("# Agent Typography proof"), "typed \(harness.document.text.prefix(30).debugDescription)")
        #expect(recoveries(trace).isEmpty, "\(recoveries(trace).count) keystrokes recovered: \(disagreements)")
    }

    // Verifies: REQ-109 — typing at the start of a heading goes on being accepted, keystroke after
    // keystroke, as the authoritative parse of each lands between them. Agent-drive run
    // 45943545906 clicked into the app on a runner, typed "Agent " before "Typography proof",
    // and the first keystroke was recovered as a COR-71 disagreement; the rest were lost.
    //
    // The second keystroke is sent without capturing a selection first, as AppKit sends it: the
    // caret is wherever the first keystroke and its reconciliation left the session's selection.
    @Test func typingAtTheStartOfAHeadingContinues() async throws {
        let trace = InMemoryEditorTrace()
        let harness = try PerformanceBoundaryTests.EditorHarness(source: "# Typography proof\n\nParagraph one.\n", trace: trace)
        let opened = harness.document.sourceVersion
        await harness.settle()
        harness.coordinator.applyProjectionIfNeeded(reason: .newSnapshot)

        harness.typeCharacter("A", at: NSRange(location: 0, length: 0))
        let first = harness.document.sourceVersion
        try #require(first != opened, "the first keystroke did not commit")
        let provisional = try #require(harness.session.presentation)
        await awaitReconciliations(trace, revision: first, count: 1)
        let differences = harness.session.presentation.map { Self.differences(provisional, $0) } ?? ["no presentation"]
        // The view's update on a new snapshot, which SwiftUI performs in the app.
        harness.coordinator.applyProjectionIfNeeded(reason: .newSnapshot)

        harness.session.updateOrigin.with(.nativeUserInput) {
            _ = harness.coordinator.textView(
                harness.textView,
                shouldChangeTextIn: NSRange(location: 1, length: 0),
                replacementString: "g"
            )
        }

        let refusals = trace.eventsMatching {
            if case .editRefused = $0 { return true }
            return false
        }
        #expect(harness.document.text.hasPrefix("# Ag"), "the second keystroke was lost: \(harness.document.text.prefix(24).debugDescription); refusals: \(refusals); session selection \(String(describing: harness.session.wysiwygModeState.selection)), presentation \(String(describing: harness.session.presentation?.id))")
        #expect(recoveries(trace).isEmpty, "a keystroke at the start of a heading was recovered: \(recoveries(trace)); provisional vs authoritative: \(differences)")
    }
}
