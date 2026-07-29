//
//  ReconciliationInvariantTests.swift
//  Markdown EditorTests
//
//  ARC-015 proof: editor-host view reconciliation is publication-free and captures no live
//  AppKit state. Every test here fails against the pre-COR-10 host, which captured selection
//  and scroll into published session state on every update pass.
//

import Testing
import AppKit
import Combine
import Foundation
@testable import Markdown_Editor

@MainActor
struct ReconciliationInvariantTests {

    /// Builds a host over a parsed document in WYSIWYG mode — the configuration that looped.
    private func makeHost(
        text: String = "# Hello\n\nSome *basic* markdown.\n"
    ) -> (MarkdownDocument, EditorSession, EditorHostView.HostCoordinator, NSView) {
        let document = MarkdownDocument()
        document.installTextForTesting(text)
        let session = EditorSession()
        session.attach(document: document)

        let index = MarkdownSourceIndex(source: text, sourceVersion: document.sourceVersion)
        guard case .success(let tree) = MarkdownParser.parse(
            text,
            sourceVersion: document.sourceVersion
        ) else {
            fatalError("fixture must parse")
        }
        session.installProjectionForTesting(
            MarkdownProjectionModel.build(tree: tree, index: index),
            tree: tree
        )

        let placement = ImagePlacementController()
        placement.attach(actions: document)
        let router = EditorActionRouter()
        router.document = document
        router.placement = placement
        let host = EditorHostView.HostCoordinator(
            document: document,
            session: session,
            placementController: placement,
            actionRouter: router
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        host.buildEditors(in: root)
        host.applyMode(session.mode, focus: false)
        return (document, session, host, root)
    }

    /// Reproduces exactly what `EditorHostView.updateNSView` does, under the same bracket.
    private func reconcile(
        _ host: EditorHostView.HostCoordinator,
        _ session: EditorSession
    ) {
        let started = DispatchTime.now().uptimeNanoseconds
        session.withViewReconciliation {
            host.syncDocumentBindings()
            host.refreshVisibleEditor()
            host.applyModeIfChanged(session.mode)
        }
        host.noteHostUpdate(durationNanos: DispatchTime.now().uptimeNanoseconds &- started)
    }

    // Verifies: REQ-094; ARC-015 — reconciling an unchanged mode mutates no session state.
    // Fails before COR-10: `applyMode` captured selection and scroll on every pass, so the
    // mutation count advanced once per reconciliation and never settled.
    @Test func unchangedModeReconciliationMutatesNoSessionState() {
        let (_, session, host, _) = makeHost()
        reconcile(host, session)

        let mutationsBefore = session.modeStateMutationCount
        let sourceBefore = session.sourceModeState
        let wysiwygBefore = session.wysiwygModeState

        for _ in 0..<25 {
            reconcile(host, session)
        }

        #expect(session.modeStateMutationCount == mutationsBefore)
        #expect(session.sourceModeState == sourceBefore)
        #expect(session.wysiwygModeState == wysiwygBefore)
        #expect(session.reconciliationViolationCount == 0)
    }

    // Verifies: REQ-094; ARC-015 — reconciliation publishes nothing, so it cannot re-dirty the
    // view being reconciled. Fails before COR-10: every pass published mode state.
    @Test func hostReconciliationPublishesNothing() {
        let (_, session, host, _) = makeHost()
        reconcile(host, session)

        var publications = 0
        let observer = session.objectWillChange.sink { _ in publications += 1 }
        defer { observer.cancel() }

        for _ in 0..<25 {
            reconcile(host, session)
        }

        #expect(publications == 0)
    }

    // Verifies: REQ-094; ARC-Q11 — an idle document settles. Driving reconciliation from its
    // own publications terminates instead of running forever.
    // Fails before COR-10: each pass produced another publication, without limit.
    @Test func idleDocumentSettlesAfterBoundedHostUpdates() {
        let (_, session, host, _) = makeHost()

        var passes = 0
        var pendingPublication = true
        let observer = session.objectWillChange.sink { _ in pendingPublication = true }
        defer { observer.cancel() }

        // Model the run loop: reconcile while the session keeps asking to be reconciled.
        while pendingPublication, passes < 100 {
            pendingPublication = false
            reconcile(host, session)
            passes += 1
        }

        #expect(passes < 100, "reconciliation never settled")
        #expect(passes <= 3)
    }

    // Verifies: REQ-094; ARC-013/015 — a programmatic selection set does not write back into
    // session state. Fails before COR-10: `textViewDidChangeSelection` wrote unconditionally,
    // so mode restoration fed itself.
    @Test func programmaticSelectionDoesNotWriteSessionState() {
        let (_, session, host, _) = makeHost()
        reconcile(host, session)

        let mutationsBefore = session.modeStateMutationCount
        session.updateOrigin.with(.selectionRestoration) {
            host.wysiwygText?.setSelectedRange(NSRange(location: 1, length: 2))
            host.sourceText?.setSelectedRange(NSRange(location: 1, length: 2))
        }

        #expect(session.modeStateMutationCount == mutationsBefore)
    }

    // Verifies: REQ-094 — native selection changes still reach the session. The origin guard
    // must silence programmatic restoration only, never real user input.
    @Test func nativeSelectionStillUpdatesSessionState() {
        let (_, session, host, _) = makeHost()
        reconcile(host, session)

        let mutationsBefore = session.modeStateMutationCount
        host.wysiwygText?.setSelectedRange(NSRange(location: 2, length: 3))

        #expect(session.modeStateMutationCount > mutationsBefore)
        #expect(session.wysiwygModeState.selection?.range.utf16 == NSRange(location: 2, length: 3))
    }

    // Verifies: REQ-096 — capturing live AppKit state during reconciliation is a fault.
    @Test func liveStateCaptureDuringReconciliationRecordsFault() {
        let document = MarkdownDocument()
        let trace = InMemoryEditorTrace()
        document.trace = trace
        document.installTextForTesting("# Hello\n")
        let session = EditorSession()
        // This test provokes the violation on purpose; the debug trap would abort the host.
        session.trapsOnReconciliationViolation = false
        session.attach(document: document)
        trace.reset()

        session.withViewReconciliation {
            session.updateSourceModeState { $0.scrollOffset = CGPoint(x: 0, y: 40) }
        }

        #expect(session.reconciliationViolationCount == 1)
        let violations = trace.eventsMatching {
            if case .viewReconciliationViolation = $0 { return true }
            return false
        }
        #expect(violations == [.viewReconciliationViolation(kind: .liveStateCapture)])
    }

    // Verifies: REQ-096 — a sustained host-update rate crosses the storm threshold exactly once
    // per window, so the pre-COR-10 loop would have reported itself.
    @Test func hostUpdateStormCrossesThresholdOnce() {
        let meter = HostUpdateMeter()
        var crossings = 0
        for _ in 0...(HostUpdateMeter.stormThreshold + 10) {
            if meter.record(durationNanos: 1_000).crossedStormThreshold {
                crossings += 1
            }
        }
        #expect(crossings == 1)
        #expect(meter.updatesInWindow > HostUpdateMeter.stormThreshold)
    }

    // Verifies: REQ-086 — mode restoration still restores each mode's own selection and scroll.
    // The capture path moved to AppKit events; the restore behavior is unchanged.
    @Test func modeChangeStillRestoresPerModeChrome() {
        let (_, session, host, _) = makeHost(text: "abcdefghij\n")

        host.sourceText?.setSelectedRange(NSRange(location: 3, length: 2))
        session.setMode(.source)
        host.applyModeIfChanged(.source)
        #expect(host.sourceText?.selectedRange() == NSRange(location: 3, length: 2))

        session.setMode(.wysiwyg)
        host.applyModeIfChanged(.wysiwyg)
        session.setMode(.source)
        host.applyModeIfChanged(.source)
        #expect(host.sourceText?.selectedRange() == NSRange(location: 3, length: 2))
    }

    // Verifies: REQ-096 — publishing observed state during reconciliation is a fault. This
    // covers the `objectWillChange` observer, which the live-capture test does not reach now
    // that mode state is unpublished.
    @Test func reentrantPublicationRecordsFault() {
        let document = MarkdownDocument()
        let trace = InMemoryEditorTrace()
        document.trace = trace
        document.installTextForTesting("# Hello\n")
        let session = EditorSession()
        session.trapsOnReconciliationViolation = false
        session.attach(document: document)
        trace.reset()

        session.withViewReconciliation {
            // `mode` is published, so this is exactly the illegal direction of flow.
            session.setMode(.source)
        }

        #expect(session.reconciliationViolationCount >= 1)
        let violations = trace.eventsMatching {
            if case .viewReconciliationViolation(let kind) = $0 { return kind == .publication }
            return false
        }
        #expect(!violations.isEmpty)
    }

    // Verifies: REQ-096 — a sustained host-update rate reaches the trace as a fault through
    // the production coordinator, not merely through the meter in isolation.
    @Test func hostUpdateStormRecordsFault() {
        let (document, session, host, _) = makeHost()
        let trace = InMemoryEditorTrace()
        document.trace = trace

        for _ in 0...(HostUpdateMeter.stormThreshold + 5) {
            reconcile(host, session)
        }

        let storms = trace.eventsMatching {
            if case .hostUpdateStorm = $0 { return true }
            return false
        }
        #expect(storms.count == 1)
        #expect(session.reconciliationViolationCount == 0)
    }

    // Verifies: REQ-094 — replacing source storage keeps the visible caret and the session
    // selection that toolbar commands act on in agreement.
    // Fails without the restore in `refreshVisibleEditor`: reverting collapses the caret to
    // the end of the new storage while the session still reports the old range.
    @Test func sourceStorageRefreshKeepsCaretAndSessionSelectionInAgreement() {
        let (document, session, host, _) = makeHost(text: "abcdefghij\n")
        session.setMode(.source)
        host.applyModeIfChanged(.source)

        host.sourceText?.setSelectedRange(NSRange(location: 4, length: 2))
        #expect(session.sourceModeState.selection.range.utf16 == NSRange(location: 4, length: 2))

        document.installTextForTesting("abcdefghij klmnop\n")
        reconcile(host, session)

        #expect(host.sourceText?.string == document.text)
        #expect(host.sourceText?.selectedRange() == session.sourceModeState.selection.range.utf16)
    }

    // Verifies: REQ-096 — a blocked main actor is reported while it is still blocked, not
    // only once it recovers. Without the threshold race in `probeOnce` only one report
    // arrives, and only after recovery.
    @Test func watchdogReportsStallWhileStillBlocked() async {
        let reported = ReportBox()
        let blocker = Task { @MainActor in
            // Occupy the main actor past the probe threshold. The blocking sleep lives in a
            // synchronous function so it genuinely holds the actor rather than suspending.
            occupyMainActor(seconds: 0.4)
        }
        await MainActorWatchdog.probeOnce(thresholdMillis: 100) { millis in
            reported.append(millis)
        }
        await blocker.value

        let values = await reported.awaitingCount(2)
        #expect(values.count == 2, "expected an immediate stall report and a recovery duration")
        #expect(values.first == 100)
        #expect((values.last ?? 0) >= 100)
    }

    // Verifies: REQ-099 — "WYSIWYG went read-only and I don't know why" must have a log line,
    // but only the transition, not every mode-state mutation that leaves availability unchanged.
    @Test func availabilityChangedRecordsOnlyOnTransition() {
        let document = MarkdownDocument()
        let trace = InMemoryEditorTrace()
        document.trace = trace
        document.installTextForTesting("# Hello\n")
        let session = EditorSession()
        session.attach(document: document)
        trace.reset()

        let snapshotID = PresentationSnapshot.ID(value: 1)
        session.updateWYSIWYGModeState { $0.availability = .editable(snapshotID) }
        session.updateWYSIWYGModeState { $0.availability = .editable(snapshotID) }
        session.updateWYSIWYGModeState { $0.scrollOffset = CGPoint(x: 0, y: 10) }

        let transitions = trace.eventsMatching {
            if case .availabilityChanged = $0 { return true }
            return false
        }
        #expect(transitions == [.availabilityChanged(editable: true, sourceRevision: document.sourceVersion)])
    }
}

/// Blocks the main actor for real, so the watchdog observes an unresponsive actor.
@MainActor
func occupyMainActor(seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: seconds)
}

/// Collects watchdog reports from a background isolation domain.
///
/// Reports arrive synchronously from a non-isolated context, so delivery into the actor is
/// itself asynchronous; `awaitingCount` waits for them rather than sampling a race.
actor ReportBox {
    private(set) var values: [UInt64] = []

    nonisolated func append(_ value: UInt64) {
        Task { await self.store(value) }
    }

    private func store(_ value: UInt64) {
        values.append(value)
    }

    func awaitingCount(_ target: Int, timeoutSeconds: Double = 2) async -> [UInt64] {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeoutSeconds * 1_000_000_000)
        while values.count < target, DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return values
    }
}
