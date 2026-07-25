//
//  MarkdownDocument.swift
//  Markdown Editor
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// NSDocument owner of canonical Markdown source, version, URL generation, and undo.
///
/// // REQ-013–REQ-019: one document/source/version/undo owner; byte-preserving I/O;
/// // versioned source transactions; operation-scoped Save; main-actor mutation;
/// // location generation for COR-02.
final class MarkdownDocument: NSDocument, ObservableObject, DocumentActionInterface {
    // MARK: - Readable types

    override class var readableTypes: [String] {
        [MarkdownContentType.identifier]
    }

    override class var writableTypes: [String] {
        [MarkdownContentType.identifier]
    }

    override class func isNativeType(_ type: String) -> Bool {
        type == MarkdownContentType.identifier
    }

    // MARK: - I/O snapshot (any thread)

    /// Byte-faithful text used by background `read` / `data(ofType:)`.
    /// Mutated under `ioLock`; never holds a live document reference for callers.
    private let ioLock = NSLock()
    nonisolated(unsafe) private var ioText: String = ""

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

    /// When true, the next `setFileURL` that assigns the first non-nil URL while untitled
    /// is treated as the expected outcome of operation-scoped Save (no generation bump).
    private var expectingUntitledSaveURL = false

    // MARK: - NSDocument lifecycle

    override init() {
        super.init()
        // REQ-002
        text = ""
        syncIOText("")
        publishedFileURL = nil
    }

    nonisolated override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        // Ensure editor state matches the I/O snapshot before hosting (read may have
        // applied bytes off-main and only scheduled the published-state hop).
        let loaded = copyIOText()
        if text != loaded {
            applyLoadedText(loaded)
        }
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
        let snapshot = copyIOText()
        return MarkdownDocumentData(text: snapshot).data()
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
        objectWillChange.send()
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

    // REQ-016: validate, mutate once, advance version, register one undo, mark changed.
    @discardableResult
    func commitSourceEdit(_ edit: SourceEdit) -> SourceEditResult {
        guard edit.expectedVersion == sourceVersion else {
            return .refused(.staleVersion)
        }
        let ns = text as NSString
        let length = ns.length
        let range = edit.range
        guard range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= length else {
            return .refused(.invalidRange)
        }

        let replaced = ns.substring(with: range)
        let newText = ns.replacingCharacters(in: range, with: edit.replacement)
        let replacementUTF16 = (edit.replacement as NSString).length
        let selection = SourceSelection(
            range: NSRange(location: range.location + replacementUTF16, length: 0)
        )

        text = newText
        sourceVersion &+= 1
        syncIOText(newText)
        // Dirty state is driven by UndoManager registration — do not also call
        // updateChangeCount(.changeDone) or undo/redo will double-count.

        let inverse = SourceEdit(
            expectedVersion: sourceVersion,
            range: NSRange(location: range.location, length: replacementUTF16),
            replacement: replaced,
            actionName: edit.actionName
        )
        if let undoManager {
            undoManager.setActionName(edit.actionName)
            undoManager.registerUndo(withTarget: self) { doc in
                _ = doc.commitSourceEdit(inverse)
            }
        }

        noteTrackedEdit(edited: range, changeInLength: replacementUTF16 - range.length)
        objectWillChange.send()
        return .committed(selection)
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
        text = value
        sourceVersion = 0
        syncIOText(value)
        updateChangeCount(.changeCleared)
    }

    // MARK: - Private

    nonisolated private func applyIOText(_ value: String) {
        ioLock.lock()
        ioText = value
        ioLock.unlock()
    }

    nonisolated private func copyIOText() -> String {
        ioLock.lock()
        let value = ioText
        ioLock.unlock()
        return value
    }

    nonisolated private func syncIOText(_ value: String) {
        applyIOText(value)
    }

    private func applyLoadedText(_ value: String) {
        text = value
        sourceVersion = 0
        activeSelectionStorage = NSRange(location: 0, length: 0)
        pendingSelection = nil
        activeTracker = nil
        activeTrackingGeneration = nil
        objectWillChange.send()
    }
}
