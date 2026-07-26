//
//  MarkdownDocument.swift
//  Markdown Editor
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// NSDocument owner of canonical Markdown source, revision, URL generation, and undo.
///
/// // REQ-013–REQ-019: one document/source/version/undo owner; byte-preserving I/O;
/// // versioned source transactions; operation-scoped Save; main-actor mutation;
/// // location generation for image placement.
/// // REQ-011/016/018/083/088/089: content-validated HistoryPatch undo;
/// // privacy-safe traces; Swift 6 complete concurrency.
final class MarkdownDocument: NSDocument, ObservableObject, DocumentActionInterface {
    // MARK: - Readable types
    // Hardcoded UTI string: class getters are called from AppKit autosave on arbitrary
    // executor contexts under Swift 6; avoid any cross-type static access here.

    nonisolated override class var readableTypes: [String] {
        ["net.daringfireball.markdown"]
    }

    nonisolated override class var writableTypes: [String] {
        ["net.daringfireball.markdown"]
    }

    nonisolated override class func isNativeType(_ type: String) -> Bool {
        type == "net.daringfireball.markdown"
    }

    // MARK: - I/O snapshot (any thread)

    // MARK: - Main-actor editor state

    /// Canonical source. Mutated only on the main actor via transactions / load.
    @Published private(set) var text: String = ""
    @Published private(set) var sourceVersion: UInt64 = 0
    @Published private(set) var locationGeneration: UInt64 = 0
    /// Mirror of `fileURL` for SwiftUI observation (NSDocument's property is not @Published).
    @Published private(set) var publishedFileURL: URL?

    let selectionRestorations = PassthroughSubject<SourceSelection, Never>()

    private var trackingGeneration: Int = 0
    private var activeTracker: InsertionRangeTracker?
    private var activeTrackingGeneration: Int?

    /// Test seam: inject Save execution (REQ-017).
    var saveExecutorOverride: DocumentSaving?

    /// Privacy-safe instrumentation sink (REQ-089).
    var trace: (any EditorTraceSink)?

    /// When true, the next `setFileURL` that assigns the first non-nil URL while untitled
    /// is treated as the expected outcome of operation-scoped Save (no generation bump).
    private var expectingUntitledSaveURL = false

    /// Open typing undo group (MutationGrouping.typing coalescing).
    private var typingGroupOpen = false
    private var undoCheckpointObserver: NSObjectProtocol?

    /// Notification center seam for observer lifecycle tests.
    var notificationCenterForTesting: NotificationCenter = .default

    // MARK: - NSDocument lifecycle

    override init() {
        super.init()
        text = ""
        publishedFileURL = nil
        undoManager?.groupsByEvent = false
        attachUndoCheckpointObserverIfNeeded()
    }

    /// Production always autosaves in place (REQ-014).
    nonisolated static var autosavesInPlaceForProduction: Bool { true }

    nonisolated override class var autosavesInPlace: Bool {
        // XCTest hosts construct documents without a document session; AppKit autosave
        // races Swift 6 isolation and clears change counts mid-assertion.
        if MarkdownAppDelegate.isRunningUnitTests { return false }
        return autosavesInPlaceForProduction
    }

    override func makeWindowControllers() {
        undoManager?.groupsByEvent = false
        attachUndoCheckpointObserverIfNeeded()
        let contentView = ContentView(document: self)
        let hosting = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 560))
        window.minSize = NSSize(width: 320, height: 240)
        window.center()
        let controller = NSWindowController(window: window)
        controller.contentViewController = hosting
        addWindowController(controller)
    }

    // REQ-015/018; ARC-011: AppKit's default serialized read — assert main thread, install canonically.
    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        precondition(
            Thread.isMainThread,
            "ARC-011 counterexample: NSDocument read invoked off-main while canConcurrentlyReadDocuments remains false"
        )
        let decoded = try MarkdownDocumentData(data: data)
        MainActor.assumeIsolated {
            self.installLoadedText(decoded.text)
        }
    }

    // REQ-015/018; ARC-011: AppKit's default serialized write — snapshot canonical text on main.
    nonisolated override func data(ofType typeName: String) throws -> Data {
        precondition(
            Thread.isMainThread,
            "ARC-011 counterexample: NSDocument data(ofType:) invoked off-main while canAsynchronouslyWrite remains false"
        )
        return MainActor.assumeIsolated {
            MarkdownDocumentData(text: self.text).data()
        }
    }

    // REQ-019: advance location generation on URL change (except expected untitled Save).
    nonisolated override var fileURL: URL? {
        get { super.fileURL }
        set {
            let previous = super.fileURL
            super.fileURL = newValue
            scheduleApplyFileURLChange(from: previous, to: newValue)
        }
    }

    /// Returns whether locationGeneration was advanced.
    @MainActor
    private func applyFileURLChange(from previous: URL?, to newValue: URL?) -> Bool {
        publishedFileURL = newValue
        guard previous != newValue else { return false }
        let wasExpectingUntitled =
            expectingUntitledSaveURL
            && previous == nil
            && newValue != nil
        if wasExpectingUntitled {
            expectingUntitledSaveURL = false
            return false
        }
        locationGeneration &+= 1
        return true
    }

    nonisolated private func scheduleApplyFileURLChange(from previous: URL?, to newValue: URL?) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                _ = self.applyFileURLChange(from: previous, to: newValue)
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    _ = self.applyFileURLChange(from: previous, to: newValue)
                }
            }
        }
    }

    // MARK: - DocumentActionInterface

    func sourceSnapshot() -> SourceSnapshot {
        SourceSnapshot(
            text: text,
            sourceVersion: sourceVersion,
            locationGeneration: locationGeneration,
            fileURL: fileURL
        )
    }

    func requestSelectionRestoration(_ selection: SourceSelection) {
        selectionRestorations.send(selection)
    }

    func beginPlacementTracking(range: SourceRange) -> Int {
        trackingGeneration &+= 1
        activeTracker = InsertionRangeTracker(range: range.utf16)
        activeTrackingGeneration = trackingGeneration
        return trackingGeneration
    }

    func endPlacementTracking(_ generation: Int) {
        if activeTrackingGeneration == generation {
            activeTracker = nil
            activeTrackingGeneration = nil
        }
    }

    func trackedPlacement(for generation: Int) -> InsertionRangeTracker? {
        guard activeTrackingGeneration == generation else { return nil }
        return activeTracker
    }

    var activePlacementTrackingGeneration: Int { activeTrackingGeneration ?? 0 }

    func noteTrackedEdit(edited: NSRange, changeInLength: Int) {
        guard var tracker = activeTracker else { return }
        tracker.applyEdit(edited: edited, changeInLength: changeInLength)
        activeTracker = tracker
    }

    var documentUndoManager: UndoManager? { undoManager }

    // REQ-016: validate revision, range, and expected content; one private apply path.
    @discardableResult
    func commitSourceMutation(_ mutation: SourceMutation) -> SourceEditResult {
        trace?.record(
            .mutationRequested(
                id: mutation.id,
                revision: mutation.expectedRevision,
                location: mutation.range.location,
                length: mutation.range.length,
                replacementLength: (mutation.replacement as NSString).length
            )
        )

        guard mutation.expectedRevision == sourceVersion else {
            trace?.record(.mutationRefused(id: mutation.id, reason: .staleVersion))
            return .refused(.staleVersion)
        }

        let ns = text as NSString
        let length = ns.length
        let range = mutation.range
        guard range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= length else {
            trace?.record(.mutationRefused(id: mutation.id, reason: .invalidRange))
            return .refused(.invalidRange)
        }

        let actual = ns.substring(with: range)
        guard actual == mutation.expectedText else {
            trace?.record(.mutationRefused(id: mutation.id, reason: .contentMismatch))
            return .refused(.contentMismatch)
        }

        let replacementUTF16 = (mutation.replacement as NSString).length
        applyReplacement(
            range: range,
            replacement: mutation.replacement
        )

        let patch = HistoryPatch.fromCommitted(mutation)
        registerHistoryUndo(for: patch, grouping: mutation.grouping)

        trace?.record(
            .mutationCommitted(
                id: mutation.id,
                newRevision: sourceVersion,
                location: range.location,
                length: range.length,
                replacementLength: replacementUTF16
            )
        )
        return .committed(mutation.selectionAfter)
    }

    /// Test / history seam: apply a patch with content validation (no revision gate).
    @discardableResult
    func applyHistoryPatchForTesting(
        _ patch: HistoryPatch,
        direction: HistoryDirection
    ) -> SourceEditResult {
        applyHistoryPatch(patch, direction: direction)
    }

    // REQ-017: operation-scoped Save without view hierarchy discovery.
    func saveDocument() async -> Bool {
        if fileURL == nil {
            expectingUntitledSaveURL = true
        }
        let bridge: DocumentSaving = saveExecutorOverride ?? NSDocumentSavingAdapter(document: self)
        let ok = await bridge.saveDocument()
        if !ok {
            expectingUntitledSaveURL = false
        }
        return ok
    }

    override func close() {
        detachUndoCheckpointObserver()
        super.close()
    }

    // MARK: - Testing helpers

    /// Install text without going through file I/O (unit tests).
    func installTextForTesting(_ value: String) {
        undoManager?.groupsByEvent = false
        attachUndoCheckpointObserverIfNeeded()
        closeTypingGroupIfNeeded()
        text = value
        sourceVersion = 0
        updateChangeCount(.changeCleared)
        undoManager?.removeAllActions()
    }

    /// Canonical load path used by serialized `read(from:ofType:)`.
    private func installLoadedText(_ value: String) {
        closeTypingGroupIfNeeded()
        text = value
        sourceVersion = 0
        activeTracker = nil
        activeTrackingGeneration = nil
        undoManager?.removeAllActions()
        updateChangeCount(.changeCleared)
    }

    // MARK: - Private mutation / history

    /// One private application path for user edits, undo, and redo.
    private func applyReplacement(
        range: NSRange,
        replacement: String
    ) {
        let ns = text as NSString
        let replacementUTF16 = (replacement as NSString).length
        let newText = ns.replacingCharacters(in: range, with: replacement)
        text = newText
        sourceVersion &+= 1
        noteTrackedEdit(edited: range, changeInLength: replacementUTF16 - range.length)
        // Dirty state is driven by UndoManager registration — do not also call
        // updateChangeCount(.changeDone) or undo/redo will double-count.
    }

    private func applyHistoryPatch(
        _ patch: HistoryPatch,
        direction: HistoryDirection
    ) -> SourceEditResult {
        guard patch.matchesCurrentContent(in: text) else {
            trace?.record(.historyRefused(direction: direction, reason: .contentMismatch))
            return .refused(.contentMismatch)
        }

        applyReplacement(
            range: patch.range,
            replacement: patch.before
        )
        requestSelectionRestoration(patch.selectionBefore)

        // Register the inverse dynamically — never call the version-gated public API.
        // While undoing/redoing, UndoManager forms the opposite operation from this registration.
        if undoManager?.isUndoing == true || undoManager?.isRedoing == true {
            typingGroupOpen = false
        }
        let inverse = patch.inverse()
        if let undoManager {
            undoManager.setActionName(patch.actionName)
            undoManager.registerUndo(withTarget: self) { doc in
                let next: HistoryDirection = (direction == .undo) ? .redo : .undo
                _ = doc.applyHistoryPatch(inverse, direction: next)
            }
        }

        trace?.record(
            .historyApplied(
                direction: direction,
                newRevision: sourceVersion,
                location: patch.range.location,
                length: patch.range.length
            )
        )
        return .committed(patch.selectionBefore)
    }

    private func registerHistoryUndo(for patch: HistoryPatch, grouping: MutationGrouping) {
        guard let undoManager else { return }
        attachUndoCheckpointObserverIfNeeded()

        switch grouping {
        case .discrete:
            closeTypingGroupIfNeeded()
            // Always open an explicit group — XCTest/host contexts may have groupingLevel 0
            // without an automatic event group (REQ-016).
            undoManager.beginUndoGrouping()
            undoManager.setActionName(patch.actionName)
            undoManager.registerUndo(withTarget: self) { [patch] doc in
                _ = doc.applyHistoryPatch(patch, direction: .undo)
            }
            undoManager.endUndoGrouping()
            trace?.record(
                .undoRegistered(actionNameLength: patch.actionName.count, groupingTyping: false)
            )
        case .typing:
            if !typingGroupOpen {
                undoManager.beginUndoGrouping()
                typingGroupOpen = true
            }
            // If a checkpoint closed the group out from under us, reopen before registering.
            if undoManager.groupingLevel == 0 {
                undoManager.beginUndoGrouping()
                typingGroupOpen = true
            }
            undoManager.setActionName(patch.actionName)
            undoManager.registerUndo(withTarget: self) { [patch] doc in
                _ = doc.applyHistoryPatch(patch, direction: .undo)
            }
            trace?.record(
                .undoRegistered(actionNameLength: patch.actionName.count, groupingTyping: true)
            )
        }
    }

    private func closeTypingGroupIfNeeded() {
        guard typingGroupOpen else { return }
        typingGroupOpen = false
        // Only end a group we actually opened — AppKit/checkpoint churn can leave
        // groupingLevel 0 while our flag was still set.
        guard let undoManager, undoManager.groupingLevel > 0 else { return }
        undoManager.endUndoGrouping()
    }

    func closeTypingUndoGroup() {
        closeTypingGroupIfNeeded()
    }

    /// Close an open typing group before undo/redo so UndoManager is never left nested.
    private func attachUndoCheckpointObserverIfNeeded() {
        guard undoCheckpointObserver == nil, let undoManager else { return }
        undoCheckpointObserver = notificationCenterForTesting.addObserver(
            forName: .NSUndoManagerCheckpoint,
            object: undoManager,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closeTypingGroupIfNeeded()
            }
        }
    }

    func detachUndoCheckpointObserver() {
        if let token = undoCheckpointObserver {
            notificationCenterForTesting.removeObserver(token)
            undoCheckpointObserver = nil
        }
        closeTypingGroupIfNeeded()
    }
}
