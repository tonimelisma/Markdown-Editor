//
//  ImagePlacementController.swift
//  Markdown Editor
//

import AppKit
import Combine
import Foundation

// REQ-060/069–076: main-actor owner of one paste/drop placement transaction.

@MainActor
final class ImagePlacementController: ObservableObject {
    enum AlertKind: Equatable {
        case error(String)
        case warning(String)
        case info(String)
    }

    @Published var alert: AlertKind?

    private var state = ImagePlacementState()
    private weak var textView: MarkdownSourceTextView?
    private var lastDocumentParent: URL?
    private var lastDocumentURL: URL?
    private var documentLocationGeneration: UInt64 = 0
    private var activeTask: Task<Void, Never>?
    private var pendingSnapshot: ImageActionSnapshot?
    private let executor = ImageIOExecutor.shared
    private var saveBridge: DocumentSaving?

    /// Test seam: inject save adapter.
    var saveBridgeOverride: DocumentSaving?

    func attach(textView: MarkdownSourceTextView) {
        self.textView = textView
    }

    func updateDocumentURL(_ url: URL?) {
        let newParent = url?.deletingLastPathComponent()
        if let old = lastDocumentParent, let newParent, old != newParent, let textView {
            // REQ-076: source-derived move warning.
            if CanonicalAssetReferenceScanner.hasBrokenReferences(
                source: textView.string,
                oldParent: old,
                newParent: newParent
            ) {
                alert = .warning(
                    "This document’s assets/ references no longer resolve after the file was moved. Companion files were not moved automatically."
                )
            }
        }
        // Untitled Save assigns the first URL for the active awaiting-save transaction — that is
        // the expected outcome, not a concurrent move. Do not bump generation in that case.
        let isExpectedUntitledSaveURL =
            state.phase == .awaitingSave
            && lastDocumentURL == nil
            && url != nil
        if lastDocumentURL != url, !isExpectedUntitledSaveURL {
            documentLocationGeneration &+= 1
        }
        lastDocumentURL = url
        lastDocumentParent = newParent

        // Resume awaiting-save when URL appears for the active transaction.
        if state.phase == .awaitingSave, let url, let snapshot = pendingSnapshot {
            Task { await self.continueAfterSave(snapshot: snapshot, documentURL: url) }
        }
    }

    // REQ-060/064: begin from already-classified immutable claims (no main-thread file I/O).
    func handleImageAction(claims: [ImageClaim], documentURL: URL?) {
        guard !claims.isEmpty else { return }
        let id = ImageActionID()
        guard let next = ImagePlacementReducer.reduce(
            state: state,
            event: .begin(id),
            actionID: nil
        ) else {
            alert = .error(ImagePlacementError.busy.userMessage)
            return
        }
        state = next
        guard let textView else {
            fail(id, .writeFailed)
            return
        }
        let selection = textView.selectedRange()
        _ = textView.beginTrackingPlacement(range: selection)
        let snapshot = ImageActionSnapshot(
            id: id,
            claims: claims,
            documentURL: documentURL,
            documentLocationGeneration: documentLocationGeneration,
            selection: selection
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

    func handleFilePromises(_ receivers: [NSFilePromiseReceiver], documentURL: URL?) {
        guard !receivers.isEmpty else { return }
        let id = ImageActionID()
        guard let next = ImagePlacementReducer.reduce(
            state: state,
            event: .begin(id),
            actionID: nil
        ) else {
            alert = .error(ImagePlacementError.busy.userMessage)
            return
        }
        state = next
        guard let textView else {
            fail(id, .writeFailed)
            return
        }
        let selection = textView.selectedRange()
        _ = textView.beginTrackingPlacement(range: selection)
        let token = FilePromiseReceiptToken()
        let snapshot = ImageActionSnapshot(
            id: id,
            claims: [.promiseToken(token)],
            documentURL: documentURL,
            documentLocationGeneration: documentLocationGeneration,
            selection: selection
        )
        pendingSnapshot = snapshot
        guard apply(.startReceivingPromises, id: id) else { return }
        activeTask = Task { await self.receivePromisesThenPlace(receivers, snapshot: snapshot, documentURL: documentURL) }
    }

    // MARK: - Internals

    private func beginUntitledSave(snapshot: ImageActionSnapshot) async {
        guard let textView else {
            fail(snapshot.id, .noDocumentURL)
            return
        }
        guard let document = DocumentSaveBridge.document(for: textView) else {
            fail(snapshot.id, .noDocumentURL)
            return
        }
        let bridge: DocumentSaving = saveBridgeOverride ?? NSDocumentSavingAdapter(document: document)
        let ok = await bridge.saveDocument()
        if !ok {
            _ = apply(.saveCancelledOrFailed, id: snapshot.id)
            textView.endTrackingPlacement(textView.activeTrackingGeneration)
            pendingSnapshot = nil
            state = ImagePlacementState()
            alert = .info("Image action cancelled — document was not saved.")
            return
        }
        // Wait for DocumentGroup URL via updateDocumentURL; if already present, continue.
        if let url = lastDocumentURL ?? textView.documentURL {
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
                selection: snapshot.selection
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

    private func runPlacement(
        snapshot: ImageActionSnapshot,
        documentURL: URL,
        promiseStaging: URL? = nil
    ) async {
        defer {
            if let promiseStaging {
                try? FileManager.default.removeItem(at: promiseStaging)
            }
        }
        guard let textView else {
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

            // REQ: prove live URL still under same parent before commit.
            let liveURL = textView.documentURL ?? lastDocumentURL
            guard let liveURL else {
                await AssetDirectoryStore.rollback(
                    pins: published.createdPins,
                    assetsPath: published.assetsPath,
                    createdAssetsDirectory: published.createdAssetsDirectory,
                    executor: executor
                )
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
            if !sameParent || snapshot.documentLocationGeneration != documentLocationGeneration {
                await AssetDirectoryStore.rollback(
                    pins: published.createdPins,
                    assetsPath: published.assetsPath,
                    createdAssetsDirectory: published.createdAssetsDirectory,
                    executor: executor
                )
                // Leave files if parent changed after publish but identity check failed — actually we rolled back created pins.
                fail(snapshot.id, .parentChanged)
                return
            }

            guard apply(.startCommitting, id: snapshot.id) else {
                await AssetDirectoryStore.rollback(
                    pins: published.createdPins,
                    assetsPath: published.assetsPath,
                    createdAssetsDirectory: published.createdAssetsDirectory,
                    executor: executor
                )
                return
            }

            guard let tracker = textView.trackedPlacement(for: textView.activeTrackingGeneration),
                  !tracker.isCancelled else {
                // REQ-072: files stay; no source insert. Release pins off the main actor.
                let pins = published.createdPins
                await executor.run {
                    for pin in pins {
                        if let pinPath = pin.pinPath { unlink(pinPath) }
                    }
                }
                _ = apply(.cancel, id: snapshot.id)
                textView.endTrackingPlacement(textView.activeTrackingGeneration)
                pendingSnapshot = nil
                state = ImagePlacementState()
                alert = .warning(
                    "Images were saved to assets/, but the insertion point changed — references were not inserted."
                )
                return
            }

            let markdown = published.published.map(\.markdown).joined(separator: "\n")
            textView.insertImageMarkdown(
                markdown,
                at: tracker.range,
                selectEmptyDescription: published.published.count == 1
            )
            let pins = published.createdPins
            await executor.run {
                for pin in pins {
                    if let pinPath = pin.pinPath { unlink(pinPath) }
                }
            }
            _ = apply(.succeed, id: snapshot.id)
            textView.endTrackingPlacement(textView.activeTrackingGeneration)
            pendingSnapshot = nil
            state = ImagePlacementState()
        } catch let error as ImagePlacementError {
            fail(snapshot.id, error)
            textView.endTrackingPlacement(textView.activeTrackingGeneration)
        } catch {
            fail(snapshot.id, .writeFailed)
            textView.endTrackingPlacement(textView.activeTrackingGeneration)
        }
    }

    @discardableResult
    private func apply(_ event: ImagePlacementEvent, id: ImageActionID) -> Bool {
        guard let next = ImagePlacementReducer.reduce(state: state, event: event, actionID: id) else {
            return false
        }
        state = next
        return true
    }

    private func fail(_ id: ImageActionID, _ error: ImagePlacementError) {
        _ = apply(.fail(error), id: id)
        textView?.endTrackingPlacement(textView?.activeTrackingGeneration ?? 0)
        pendingSnapshot = nil
        state = ImagePlacementState()
        alert = .error(error.userMessage)
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
            selection: NSRange(location: 0, length: 0)
        )
    }
}
