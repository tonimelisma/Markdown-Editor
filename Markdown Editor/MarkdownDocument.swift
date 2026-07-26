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
/// // location generation for COR-02.
/// // REQ-011/016/018/083/088/089: content-validated HistoryPatch undo; Mutex snapshots;
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

    /// Byte-faithful text used by background `read` / `data(ofType:)`.
    /// // REQ-018/088: Sendable Mutex box — no `nonisolated(unsafe)`.
    nonisolated private let ioText = DocumentIOText()

    /// Exposes the I/O box for concurrent snapshot tests without MainActor hops.
    nonisolated var ioTextForTesting: DocumentIOText { ioText }

    // MARK: - Main-actor editor state

    /// Canonical source. Mutated only on the main actor via transactions / load.
    @Published private(set) var text: String = ""
    @Published private(set) var sourceVersion: UInt64 = 0
    @Published private(set) var locationGeneration: UInt64 = 0
    /// Mirror of `fileURL` for SwiftUI observation (NSDocument's property is not @Published).
    @Published private(set) var publishedFileURL: URL?

    private var activeSelectionStorage = NSRange(location: 0, length: 0)
    var pendingSelection: NSRange?

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

    // MARK: - NSDocument lifecycle

    override init() {
        super.init()
        text = ""
        syncIOText("")
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
        // Ensure editor state matches the I/O snapshot before hosting (read may have
        // applied bytes off-main and only scheduled the published-state hop).
        let loaded = copyIOText()
        if text != loaded {
            applyLoadedText(loaded)
        }
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

    // REQ-015: background read uses byte snapshot only — never main.sync (deadlock risk).
    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        let decoded = try MarkdownDocumentData(data: data)
        applyIOText(decoded.text)
        scheduleApplyLoadedText(decoded.text)
    }

    // REQ-015: background write uses byte snapshot only.
    nonisolated override func data(ofType typeName: String) throws -> Data {
        ioText.data()
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

    nonisolated private func scheduleApplyLoadedText(_ value: String) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.applyLoadedText(value)
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.applyLoadedText(value)
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

    var activeSelection: NSRange { activeSelectionStorage }

    func reportActiveSelection(_ range: NSRange) {
        activeSelectionStorage = range
    }

    func beginPlacementTracking(range: NSRange) -> Int {
        trackingGeneration &+= 1
        activeTracker = InsertionRangeTracker(range: range)
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

    // Compatibility adapter — builds a content-validated SourceMutation (discrete).
    // REQ-016: Source/COR-02 callers keep compiling.
    @discardableResult
    func commitSourceEdit(_ edit: SourceEdit) -> SourceEditResult {
        let ns = text as NSString
        let length = ns.length
        let expectedText: String
        if edit.range.location >= 0,
           edit.range.length >= 0,
           NSMaxRange(edit.range) <= length {
            expectedText = ns.substring(with: edit.range)
        } else {
            expectedText = ""
        }
        let replacementUTF16 = (edit.replacement as NSString).length
        let mutation = SourceMutation(
            expectedRevision: edit.expectedVersion,
            range: edit.range,
            expectedText: expectedText,
            replacement: edit.replacement,
            selectionBefore: SourceSelection(range: activeSelectionStorage),
            selectionAfter: SourceSelection(
                range: NSRange(location: edit.range.location + replacementUTF16, length: 0)
            ),
            actionName: edit.actionName,
            grouping: .discrete
        )
        return commitSourceMutation(mutation)
    }

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
            replacement: mutation.replacement,
            selectionAfter: mutation.selectionAfter
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

    // MARK: - Testing helpers

    /// Install text without going through file I/O (unit tests).
    func installTextForTesting(_ value: String) {
        undoManager?.groupsByEvent = false
        attachUndoCheckpointObserverIfNeeded()
        closeTypingGroupIfNeeded()
        text = value
        sourceVersion = 0
        syncIOText(value)
        activeSelectionStorage = NSRange(location: 0, length: 0)
        pendingSelection = nil
        updateChangeCount(.changeCleared)
        undoManager?.removeAllActions()
    }

    // MARK: - Private mutation / history

    /// One private application path for user edits, undo, and redo.
    private func applyReplacement(
        range: NSRange,
        replacement: String,
        selectionAfter: SourceSelection
    ) {
        let ns = text as NSString
        let replacementUTF16 = (replacement as NSString).length
        let newText = ns.replacingCharacters(in: range, with: replacement)
        text = newText
        sourceVersion &+= 1
        syncIOText(newText)
        activeSelectionStorage = selectionAfter.range
        pendingSelection = selectionAfter.range
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
            replacement: patch.before,
            selectionAfter: patch.selectionBefore
        )

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
        undoManager?.endUndoGrouping()
        typingGroupOpen = false
    }

    /// Close an open typing group before undo/redo so UndoManager is never left nested.
    private func attachUndoCheckpointObserverIfNeeded() {
        guard undoCheckpointObserver == nil, let undoManager else { return }
        undoCheckpointObserver = NotificationCenter.default.addObserver(
            forName: .NSUndoManagerCheckpoint,
            object: undoManager,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closeTypingGroupIfNeeded()
            }
        }
    }

    // MARK: - I/O helpers

    nonisolated private func applyIOText(_ value: String) {
        ioText.store(value)
    }

    nonisolated private func copyIOText() -> String {
        ioText.load()
    }

    nonisolated private func syncIOText(_ value: String) {
        applyIOText(value)
    }

    private func applyLoadedText(_ value: String) {
        closeTypingGroupIfNeeded()
        text = value
        sourceVersion = 0
        activeSelectionStorage = NSRange(location: 0, length: 0)
        pendingSelection = nil
        activeTracker = nil
        activeTrackingGeneration = nil
    }
}
