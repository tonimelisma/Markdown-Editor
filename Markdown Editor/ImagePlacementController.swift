//
//  ImagePlacementController.swift
//  Markdown Editor
//

import AppKit
import Combine
import Foundation

// REQ-060/069–076: main-actor owner of one paste/drop placement transaction.
// REQ-017/019: uses DocumentActionInterface — no view-derived document lookup.

@MainActor
final class ImagePlacementController: ObservableObject {
    enum AlertKind: Equatable {
        case error(String)
        case warning(String)
        case info(String)

        var severity: AlertSeverity {
            switch self {
            case .error: return .error
            case .warning: return .warning
            case .info: return .info
            }
        }
    }

    @Published private(set) var alert: AlertKind?

    private var state = ImagePlacementState()
    private weak var actions: DocumentActionInterface?
    /// REQ-101/102; ARC-017. Not exposed on `DocumentActionInterface`: that protocol is an
    /// editor-neutral document surface, and widening it just for logging is unnecessary when a
    /// direct sink works — set by the same caller that calls `attach(actions:)`.
    weak var trace: (any EditorTraceSink)?
    private var lastDocumentParent: URL?
    private var lastDocumentURL: URL?
    private var documentLocationGeneration: UInt64 = 0
    private var activeTask: Task<Void, Never>?
    private var pendingSnapshot: ImageActionSnapshot?
    private var pendingMoveReferenceCheck: (oldParent: URL, newParent: URL)?
    private let executor = ImageIOExecutor.shared
    private var activeTrackingGeneration: Int = 0

    /// Test seam: inject save adapter.
    var saveBridgeOverride: DocumentSaving?

    func attach(actions: DocumentActionInterface) {
        self.actions = actions
    }

    /// REQ-102; ARC-017: the only way to raise a user-visible alert, so a presented failure or
    /// warning can never be absent from the run log. Do not assign `alert` anywhere else.
    func presentAlert(_ kind: AlertKind, reason: AlertReason) {
        alert = kind
        trace?.record(route: .userAlertPresented, .userAlertPresented(severity: kind.severity, reason: reason))
    }

    func dismissAlert() {
        alert = nil
    }

    func updateDocumentURL(_ url: URL?) {
        let newParent = url?.deletingLastPathComponent()
        if let old = lastDocumentParent, let newParent, old != newParent {
            // REQ-076/112: a move can race the asynchronous authoritative parse. Retain the
            // location pair until canonical references represent the current source, rather
            // than inspecting a stale parse result or reparsing Markdown here.
            pendingMoveReferenceCheck = (old, newParent)
            evaluatePendingMoveReferenceCheck()
        }
        // REQ-019: location generation is owned by the document; sync the mirror used in snapshots.
        if let actions {
            documentLocationGeneration = actions.sourceSnapshot().locationGeneration
        }
        lastDocumentURL = url
        lastDocumentParent = newParent

        // Resume awaiting-save when URL appears for the active transaction.
        if state.phase == .awaitingSave, let url, let snapshot = pendingSnapshot {
            Task { await self.continueAfterSave(snapshot: snapshot, documentURL: url) }
        }
    }

    /// Called when the document publishes a new authoritative reference set.
    func canonicalAssetReferencesDidUpdate() {
        evaluatePendingMoveReferenceCheck()
    }

    private func evaluatePendingMoveReferenceCheck() {
        guard let pending = pendingMoveReferenceCheck, let actions else { return }
        let references = actions.canonicalAssetReferences
        guard references.sourceVersion == actions.sourceSnapshot().sourceVersion else { return }
        pendingMoveReferenceCheck = nil
        if references.hasBrokenReferences(oldParent: pending.oldParent, newParent: pending.newParent) {
            presentAlert(
                .warning(
                    "This document’s assets/ references no longer resolve after the file was moved. Companion files were not moved automatically."
                ),
                reason: .brokenReferencesAfterMove
            )
        }
    }

    // REQ-060/064: begin from already-classified immutable claims (no main-thread file I/O).
    func handleImageAction(intent: ImagePlacementIntent, documentURL: URL?) {
        guard !intent.claims.isEmpty else { return }
        let id = ImageActionID()
        guard let next = ImagePlacementReducer.reduce(
            state: state,
            event: .begin(id),
            actionID: nil
        ) else {
            // REQ-101: rejected before acceptance — `state` is untouched (the already-active
            // placement continues undisturbed), so this records the attempt and its typed
            // outcome directly rather than through `apply`/`fail`, neither of which apply here.
            trace?.record(route: .imagePlacementStarted, .imagePlacementStarted(claimCount: intent.claims.count))
            trace?.record(route: .imagePlacementFailed, .imagePlacementFailed(reason: .busy, phase: state.phase))
            presentAlert(.error(ImagePlacementError.busy.userMessage), reason: .placement(.busy))
            return
        }
        recordPhaseIfChanged(from: state.phase, to: next.phase)
        state = next
        trace?.record(route: .imagePlacementStarted, .imagePlacementStarted(claimCount: intent.claims.count))
        guard let actions else {
            fail(id, .writeFailed)
            return
        }
        let live = actions.sourceSnapshot()
        guard live.sourceVersion == intent.target.sourceRevision.value,
              live.locationGeneration == intent.target.locationGeneration else {
            fail(id, .parentChanged)
            return
        }
        documentLocationGeneration = live.locationGeneration
        activeTrackingGeneration = actions.beginPlacementTracking(range: intent.target.sourceSelection.range)
        let snapshot = ImageActionSnapshot(
            id: id,
            claims: intent.claims,
            documentURL: documentURL,
            documentLocationGeneration: live.locationGeneration,
            sourceRevision: intent.target.sourceRevision,
            selection: intent.target.sourceSelection,
            operationID: intent.target.operationID
        )
        pendingSnapshot = snapshot

        if let documentURL {
            activeTask = Task { await self.runPlacement(snapshot: snapshot, documentURL: documentURL) }
        } else {
            // REQ-075
            guard apply(.startAwaitingSave, id: id) else { return }
            Task { await self.beginUntitledSave(snapshot: snapshot) }
        }
    }

    func handleFilePromises(
        _ receivers: [NSFilePromiseReceiver],
        target: ImagePlacementTarget,
        documentURL: URL?
    ) {
        guard !receivers.isEmpty else { return }
        let id = ImageActionID()
        guard let next = ImagePlacementReducer.reduce(
            state: state,
            event: .begin(id),
            actionID: nil
        ) else {
            // REQ-101: see the matching branch in handleImageAction above.
            trace?.record(route: .imagePlacementStarted, .imagePlacementStarted(claimCount: receivers.count))
            trace?.record(route: .imagePlacementFailed, .imagePlacementFailed(reason: .busy, phase: state.phase))
            presentAlert(.error(ImagePlacementError.busy.userMessage), reason: .placement(.busy))
            return
        }
        recordPhaseIfChanged(from: state.phase, to: next.phase)
        state = next
        trace?.record(route: .imagePlacementStarted, .imagePlacementStarted(claimCount: receivers.count))
        guard let actions else {
            fail(id, .writeFailed)
            return
        }
        let live = actions.sourceSnapshot()
        guard live.sourceVersion == target.sourceRevision.value,
              live.locationGeneration == target.locationGeneration else {
            fail(id, .parentChanged)
            return
        }
        documentLocationGeneration = live.locationGeneration
        activeTrackingGeneration = actions.beginPlacementTracking(range: target.sourceSelection.range)
        let token = FilePromiseReceiptToken()
        let snapshot = ImageActionSnapshot(
            id: id,
            claims: [.promiseToken(token)],
            documentURL: documentURL,
            documentLocationGeneration: live.locationGeneration,
            sourceRevision: target.sourceRevision,
            selection: target.sourceSelection,
            operationID: target.operationID
        )
        pendingSnapshot = snapshot
        guard apply(.startReceivingPromises, id: id) else { return }
        activeTask = Task { await self.receivePromisesThenPlace(receivers, snapshot: snapshot, documentURL: documentURL) }
    }

    // MARK: - Internals

    private func beginUntitledSave(snapshot: ImageActionSnapshot) async {
        guard let actions else {
            fail(snapshot.id, .noDocumentURL)
            return
        }
        let bridge: DocumentSaving = saveBridgeOverride ?? DocumentActionSavingAdapter(actions: actions)
        switch await bridge.saveDocument() {
        case .succeeded:
            break
        case .cancelled:
            _ = apply(.saveCancelledOrFailed, id: snapshot.id)
            actions.endPlacementTracking(activeTrackingGeneration)
            pendingSnapshot = nil
            resetToIdle()
            presentAlert(
                .info("Image action cancelled — document was not saved."),
                reason: .placement(.saveCancelled)
            )
            return
        case .failed:
            fail(snapshot.id, .saveFailed)
            return
        }
        // Wait for URL via updateDocumentURL; if already present, continue.
        if let url = lastDocumentURL ?? actions.sourceSnapshot().fileURL {
            await continueAfterSave(snapshot: snapshot, documentURL: url)
        }
        // Otherwise updateDocumentURL will resume.
    }

    private func continueAfterSave(snapshot: ImageActionSnapshot, documentURL: URL) async {
        guard state.phase == .awaitingSave, state.activeID == snapshot.id else { return }
        guard apply(.saveSucceeded, id: snapshot.id) else { return }
        await runPlacement(snapshot: snapshot, documentURL: documentURL)
    }

    private func receivePromisesThenPlace(
        _ receivers: [NSFilePromiseReceiver],
        snapshot: ImageActionSnapshot,
        documentURL: URL?
    ) async {
        do {
            let result = try await FilePromiseBridge.receive(
                receivers,
                operationQueue: executor.underlyingQueue
            )
            guard apply(.promisesReceived, id: snapshot.id) else {
                try? FileManager.default.removeItem(at: result.stagingDirectory)
                return
            }
            let claims = result.urls.map { ImageClaim.fileURL($0, providerName: $0.lastPathComponent, declaredType: nil) }
            let updated = ImageActionSnapshot(
                id: snapshot.id,
                claims: claims,
                documentURL: documentURL,
                documentLocationGeneration: snapshot.documentLocationGeneration,
                sourceRevision: snapshot.sourceRevision,
                selection: snapshot.selection,
                operationID: snapshot.operationID
            )
            pendingSnapshot = updated
            if let documentURL {
                await runPlacement(snapshot: updated, documentURL: documentURL, promiseStaging: result.stagingDirectory)
            } else {
                guard apply(.startAwaitingSave, id: snapshot.id) else {
                    try? FileManager.default.removeItem(at: result.stagingDirectory)
                    return
                }
                // Stash promise staging for cleanup after save path — attach as file URLs already resolved.
                await beginUntitledSave(snapshot: updated)
                try? FileManager.default.removeItem(at: result.stagingDirectory)
            }
        } catch let error as ImagePlacementError {
            fail(snapshot.id, error)
        } catch {
            fail(snapshot.id, .promiseFailed)
        }
    }

    /// REQ-101: routes every rollback through one place so a removal is always recorded, the
    /// same discipline REQ-102/ARC-017 applies to alerts. Internal, not private: lets tests
    /// drive a real rollback directly with a genuine `AssetPublishResult` rather than
    /// orchestrating the precise async timing a full end-to-end `runPlacement` rollback needs.
    func rollbackAndRecord(_ published: AssetPublishResult) async {
        let removedCount = await AssetDirectoryStore.rollback(
            pins: published.createdPins,
            assetsPath: published.assetsPath,
            createdAssetsDirectory: published.createdAssetsDirectory,
            executor: executor
        )
        trace?.record(route: .imagePlacementRolledBack, .imagePlacementRolledBack(removedFileCount: removedCount))
    }

    private func runPlacement(
        snapshot: ImageActionSnapshot,
        documentURL: URL,
        promiseStaging: URL? = nil
    ) async {
        let placementStart = DispatchTime.now().uptimeNanoseconds
        defer {
            if let promiseStaging {
                try? FileManager.default.removeItem(at: promiseStaging)
            }
        }
        guard let actions else {
            fail(snapshot.id, .writeFailed)
            return
        }
        guard apply(.startStaging, id: snapshot.id) else { return }

        do {
            let artifacts = try await ImageBatchPreflight.stage(claims: snapshot.claims, executor: executor)
            let stagingParent = artifacts.first?.stagingURL.deletingLastPathComponent()
            defer {
                if let stagingParent {
                    try? FileManager.default.removeItem(at: stagingParent)
                }
            }

            guard apply(.startPublishing, id: snapshot.id) else { return }
            let published = try await AssetDirectoryStore.publish(
                artifacts: artifacts,
                documentURL: documentURL,
                executor: executor
            )
            let totalBytes = artifacts.reduce(0) { $0 + $1.byteCount }
            trace?.record(route: .assetDirectoryPublished, .assetDirectoryPublished(fileCount: artifacts.count, totalBytes: totalBytes))

            // REQ: prove live URL still under same parent before commit.
            let liveURL = actions.sourceSnapshot().fileURL ?? lastDocumentURL
            guard let liveURL else {
                await rollbackAndRecord(published)
                fail(snapshot.id, .documentMoved)
                return
            }
            let liveParent = liveURL.deletingLastPathComponent()
            let sameParent: Bool = await executor.run {
                let fd = try? POSIXFileOps.openDirectory(liveParent.path)
                defer { if let fd { close(fd) } }
                guard let fd,
                      let id = try? POSIXFileOps.fstatIdentity(fd) else { return false }
                return id.device == published.parentIdentity.device
                    && id.inode == published.parentIdentity.inode
            }
            let liveGeneration = actions.sourceSnapshot().locationGeneration
            documentLocationGeneration = liveGeneration
            if !sameParent || snapshot.documentLocationGeneration != liveGeneration {
                await rollbackAndRecord(published)
                fail(snapshot.id, .parentChanged)
                return
            }

            guard apply(.startCommitting, id: snapshot.id) else {
                await rollbackAndRecord(published)
                return
            }

            guard let tracker = actions.trackedPlacement(for: activeTrackingGeneration),
                  !tracker.isCancelled else {
                // REQ-072: files stay; no source insert. Release pins off the main actor.
                let pins = published.createdPins
                await executor.run {
                    for pin in pins {
                        if let pinPath = pin.pinPath { unlink(pinPath) }
                    }
                }
                _ = apply(.cancel, id: snapshot.id)
                actions.endPlacementTracking(activeTrackingGeneration)
                pendingSnapshot = nil
                resetToIdle()
                presentAlert(
                    .warning(
                        "Images were saved to assets/, but the insertion point changed — references were not inserted."
                    ),
                    reason: .insertionPointChangedAfterCommit
                )
                return
            }

            let markdown = published.published.map(\.markdown).joined(separator: "\n")
            let snap = actions.sourceSnapshot()
            let selectionBefore = snapshot.selection
            guard let mutation = SourceMutation.exact(
                snapshot: snap,
                range: tracker.range,
                replacement: markdown,
                selectionBefore: selectionBefore,
                actionName: "Insert Image",
                grouping: .discrete
            ) else {
                await rollbackAndRecord(published)
                fail(snapshot.id, .writeFailed)
                return
            }
            switch actions.commitSourceMutation(mutation) {
            case .committed:
                if published.published.count == 1 {
                    let descStart = tracker.range.location + 2
                    let pending = SourceSelection(utf16: NSRange(location: descStart, length: 0))
                    actions.requestSelectionRestoration(pending)
                } else {
                    let end = tracker.range.location + (markdown as NSString).length
                    let pending = SourceSelection(utf16: NSRange(location: end, length: 0))
                    actions.requestSelectionRestoration(pending)
                }
            case .refused:
                await rollbackAndRecord(published)
                fail(snapshot.id, .writeFailed)
                return
            }
            let pins = published.createdPins
            await executor.run {
                for pin in pins {
                    if let pinPath = pin.pinPath { unlink(pinPath) }
                }
            }
            _ = apply(.succeed, id: snapshot.id)
            let committedBytes = artifacts.reduce(0) { $0 + $1.byteCount }
            trace?.record(route: .imagePlacementCommitted, .imagePlacementCommitted(
                    fileCount: published.published.count,
                    totalBytes: committedBytes,
                    durationNanos: DispatchTime.now().uptimeNanoseconds - placementStart
                )
            )
            actions.endPlacementTracking(activeTrackingGeneration)
            pendingSnapshot = nil
            resetToIdle()
        } catch let partial as PartialPublishRollback {
            // REQ-101: the store already rolled back internally (a later artifact in this batch
            // failed after an earlier one published) — report that outcome the same way a
            // controller-driven rollback does, then fail with the underlying reason.
            trace?.record(route: .imagePlacementRolledBack, .imagePlacementRolledBack(removedFileCount: partial.removedFileCount))
            fail(snapshot.id, partial.underlying)
            actions.endPlacementTracking(activeTrackingGeneration)
        } catch let error as ImagePlacementError {
            fail(snapshot.id, error)
            actions.endPlacementTracking(activeTrackingGeneration)
        } catch {
            fail(snapshot.id, .writeFailed)
            actions.endPlacementTracking(activeTrackingGeneration)
        }
    }

    /// REQ-101: recorded here, once, so every phase transition reaches the log regardless of
    /// which call site drives it — including the two `.begin` sites, which apply the reducer
    /// directly rather than through `apply(_:id:)` below (the reducer's own UUID-gating requires
    /// `actionID: nil` for `.begin`, which `apply(_:id:)`'s signature does not allow).
    private func recordPhaseIfChanged(from previous: ImagePlacementPhase, to next: ImagePlacementPhase) {
        guard next != previous else { return }
        trace?.record(route: .imagePlacementPhase, .imagePlacementPhase(from: previous, to: next))
    }

    /// REQ-101: every terminal reset to a fresh (idle) `ImagePlacementState` goes through here —
    /// `state = ImagePlacementState()` directly, without this, is itself an unrecorded phase
    /// transition (e.g. committed → idle, failed → idle, cancelled → idle), even though the
    /// transition INTO that terminal phase was recorded via `apply(_:id:)` moments earlier.
    private func resetToIdle() {
        recordPhaseIfChanged(from: state.phase, to: .idle)
        state = ImagePlacementState()
    }

    @discardableResult
    private func apply(_ event: ImagePlacementEvent, id: ImageActionID) -> Bool {
        guard let next = ImagePlacementReducer.reduce(state: state, event: event, actionID: id) else {
            return false
        }
        recordPhaseIfChanged(from: state.phase, to: next.phase)
        state = next
        return true
    }

    private func fail(_ id: ImageActionID, _ error: ImagePlacementError) {
        let phaseBeforeFailure = state.phase
        _ = apply(.fail(error), id: id)
        actions?.endPlacementTracking(activeTrackingGeneration)
        pendingSnapshot = nil
        // REQ-101: record why before recording the reset it caused, so the run log reads in
        // causal order rather than showing the terminal idle transition before its reason.
        trace?.record(route: .imagePlacementFailed, .imagePlacementFailed(reason: error, phase: phaseBeforeFailure))
        resetToIdle()
        presentAlert(.error(error.userMessage), reason: .placement(error))
    }

    /// REQ-101: Add Image may become stale while its picker is open. No placement state was ever
    /// accepted in that case, so record its known claims and typed rejection without mutating an
    /// unrelated active operation or presenting a new alert.
    func recordRejectedImageAction(claimCount: Int, reason: ImagePlacementError) {
        guard claimCount > 0 else { return }
        trace?.record(route: .imagePlacementStarted, .imagePlacementStarted(claimCount: claimCount))
        trace?.record(route: .imagePlacementFailed, .imagePlacementFailed(reason: reason, phase: state.phase))
    }

    // Test helpers
    var phaseForTesting: ImagePlacementPhase { state.phase }
    var documentLocationGenerationForTesting: UInt64 { documentLocationGeneration }

    func prepareUntitledPlacementForTesting(claims: [ImageClaim]) {
        let id = ImageActionID()
        state = ImagePlacementReducer.reduce(state: .init(), event: .begin(id), actionID: nil) ?? state
        _ = apply(.startAwaitingSave, id: id)
        pendingSnapshot = ImageActionSnapshot(
            id: id,
            claims: claims,
            documentURL: nil,
            documentLocationGeneration: documentLocationGeneration,
            sourceRevision: SourceRevision(value: 0),
            selection: SourceSelection(utf16: NSRange(location: 0, length: 0)),
            operationID: UUID()
        )
    }
}

/// Adapts DocumentActionInterface Save into DocumentSaving for the existing bridge seam.
@MainActor
final class DocumentActionSavingAdapter: DocumentSaving {
    private let actions: DocumentActionInterface
    init(actions: DocumentActionInterface) { self.actions = actions }
    func saveDocument() async -> DocumentSaveOutcome {
        await actions.saveDocument()
    }
}
