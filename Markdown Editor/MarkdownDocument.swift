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
    private(set) var canonicalAssetReferences = CanonicalAssetReferences(values: [])
    /// Derived asset-reference changes matter to image placement, not to the document view's
    /// source/projection lifecycle. Keeping this separate from `objectWillChange` prevents an
    /// authoritative parse from scheduling itself again through `EditorSession`.
    let canonicalAssetReferenceUpdates = PassthroughSubject<CanonicalAssetReferences, Never>()
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

    /// REQ-100: true once the Data-based `read(from:ofType:)` has run during the current
    /// URL-based read attempt — see the URL-based override for why this exists.
    private var didReachDataRead = false

    /// REQ-100: true once `installLoadedText` has completed at least once for this document
    /// instance. On its own this still misclassifies one edge case: a document saved for the
    /// first time while still untouched (sourceVersion 0, never yet read from a file) and then
    /// reverted — that revert is also this instance's first-ever `read(from:ofType:)` call, so
    /// `hasCompletedInitialLoad` is false there too. `isRevertingViaAppKit` below covers exactly
    /// that case.
    private var hasCompletedInitialLoad = false

    /// REQ-100: true while AppKit's dedicated revert entry point is in progress. Distinguishes
    /// a genuine revert from a first-ever load even when both are, from this instance's own
    /// history, "the first time read(from:ofType:) ran" — see `hasCompletedInitialLoad`.
    private var isRevertingViaAppKit = false

    /// REQ-100: incremented every time `recordSaveOutcome` records anything. `saveDocument()`
    /// compares this before/after to detect a save that never reached `save(to:ofType:for:
    /// completionHandler:)` at all — the destination was never determined, e.g. the user
    /// cancelled the Save panel for an untitled document — so that outcome is not silently
    /// unrecorded merely because it took a different AppKit path than a write that was attempted.
    private var saveOutcomeSequence: UInt64 = 0

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
        // REQ-095: production instrumentation is wired at construction. Before COR-10 the
        // `trace` property was never assigned outside tests, so shipping builds produced no
        // diagnostics at all.
        if let log = DiagnosticLog.shared {
            trace = JSONLinesEditorTrace(log: log)
        }
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
        trace?.record(.documentOpened(utf16Count: (text as NSString).length))
        let contentView = ContentView(document: self)
        let hosting = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // REQ-104: the screenshot verification may make the window taller so one capture can
        // show every semantic construct at once. Width stays at the default, because the default
        // width is what the reading measure and the untruncated toolbar are reviewed against.
        window.setContentSize(NSSize(width: 720, height: MarkdownAppDelegate.smokeWindowHeight ?? 560))
        window.minSize = NSSize(width: 320, height: 240)
        window.center()
        let controller = NSWindowController(window: window)
        controller.contentViewController = hosting
        addWindowController(controller)
    }

    // REQ-100: the one override AppKit routes every save through — manual Save, Save As,
    // autosave-in-place, and the delegate-based DocumentSaveBridge path this app's own
    // operation-scoped saveDocument() uses — verified empirically (both real call paths land
    // here, on the main thread) rather than assumed, since neither is documented as the sole
    // entry point. Recording once here, rather than in saveDocument(), avoids double-counting
    // a save that reaches AppKit through either route.
    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let utf16Count = (text as NSString).length
        trace?.record(.documentSaveStarted(utf16Count: utf16Count))
        let start = DispatchTime.now().uptimeNanoseconds
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            self?.recordSaveOutcome(error: error, utf16Count: utf16Count, startUptimeNanos: start)
            completionHandler(error)
        }
    }

    /// REQ-100: extracted so the outcome→trace mapping is directly testable without driving a
    /// genuine AppKit save failure — provoking one deterministically and quickly in a headless
    /// test host proved unreliable (AppKit's own save-error recovery flow can block for tens of
    /// seconds). The integration this wraps (`super.save` actually reaching this completion) is
    /// unchanged production code, verified by construction — every save path in this app,
    /// including the delegate-based DocumentSaveBridge this app's own operation-scoped
    /// saveDocument() uses, routes through this override.
    func recordSaveOutcome(error: Error?, utf16Count: Int, startUptimeNanos: UInt64) {
        saveOutcomeSequence &+= 1
        if error != nil {
            trace?.record(.documentSaveFailed(reason: .saveFailedOrCancelled))
        } else {
            let durationNanos = DispatchTime.now().uptimeNanoseconds - startUptimeNanos
            trace?.record(
                .documentSaveSucceeded(
                    utf16Count: utf16Count,
                    sourceRevision: sourceVersion,
                    durationNanos: durationNanos
                )
            )
        }
    }

    // REQ-100: AppKit calls this URL-based override first; its default implementation reads the
    // URL into Data and only then calls the Data-based override below. A failure reading the
    // URL itself — file removed, unreadable, permission denied — never reaches that override,
    // so without this, REQ-100 would go unrecorded for exactly the load failures a user most
    // needs a diagnostic for. `didReachDataRead` distinguishes that case from a content-decode
    // failure, which the Data-based override below already records — otherwise this would
    // double-record every invalid-UTF-8 failure too, since that error also propagates up
    // through this method.
    nonisolated override func read(from url: URL, ofType typeName: String) throws {
        MainActor.assumeIsolated { self.didReachDataRead = false }
        do {
            try super.read(from: url, ofType: typeName)
        } catch {
            MainActor.assumeIsolated {
                guard !self.didReachDataRead else { return }
                self.trace?.record(.documentLoadFailed(reason: .fileUnreadable))
            }
            throw error
        }
    }

    // REQ-100: NSDocument's dedicated "Revert to Saved" entry point, distinct from the initial
    // open path. See isRevertingViaAppKit's declaration for why this override exists.
    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        isRevertingViaAppKit = true
        defer { isRevertingViaAppKit = false }
        try super.revert(toContentsOf: url, ofType: typeName)
    }

    // REQ-015/018; ARC-011: AppKit's default serialized read — assert main thread, install canonically.
    // REQ-100: the only throw site is invalid UTF-8; record it before rethrowing so NSDocument's
    // own error presentation is unchanged.
    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        precondition(
            Thread.isMainThread,
            "ARC-011 counterexample: NSDocument read invoked off-main while canConcurrentlyReadDocuments remains false"
        )
        MainActor.assumeIsolated { self.didReachDataRead = true }
        do {
            let decoded = try MarkdownDocumentData(data: data)
            MainActor.assumeIsolated {
                self.installLoadedText(decoded.text)
            }
        } catch {
            MainActor.assumeIsolated {
                self.trace?.record(.documentLoadFailed(reason: .invalidUTF8))
            }
            throw error
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
            // COR-30: `publishedFileURL`, not the live `super.fileURL`. AppKit can assign
            // `fileURL` off-main, and the matching `locationGeneration` bump then lands on a
            // later main-actor hop — so reading the live URL here could pair a NEW url with an
            // OLD generation, and every asynchronous identity check in the app is keyed on that
            // pair. Both fields are written inside one main-actor block in
            // `applyFileURLChange`, so reading the published mirror is always self-consistent.
            // It may be one hop stale, which the identity checks already handle correctly;
            // inconsistent is what they cannot handle.
            locationGeneration: locationGeneration,
            fileURL: publishedFileURL
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

    // REQ-017/100: operation-scoped Save without view hierarchy discovery; record the outcome.
    // The AppKit bridge reports only a Boolean. A false completion that reached our save override
    // is a failed write; one that never reached it is a cancelled untitled Save panel.
    func saveDocument() async -> DocumentSaveOutcome {
        if fileURL == nil {
            expectingUntitledSaveURL = true
        }
        let sequenceBefore = saveOutcomeSequence
        if let saveExecutorOverride {
            let outcome = await saveExecutorOverride.saveDocument()
            if outcome != .succeeded {
                expectingUntitledSaveURL = false
                // Test and controlled-operation adapters bypass AppKit's save override, so they
                // must still leave the same privacy-safe document-I/O evidence as that path.
                trace?.record(.documentSaveFailed(reason: .saveFailedOrCancelled))
            }
            return outcome
        }
        let didSave = await DocumentSaveBridge.save(self)
        if !didSave {
            expectingUntitledSaveURL = false
            guard saveOutcomeSequence == sequenceBefore else { return .failed }
            // REQ-100: cancellation never reaches save(to:ofType:for:completionHandler:), so
            // record its closed-enum document-I/O failure shape here while returning its more
            // precise operation outcome to callers such as image placement.
            trace?.record(.documentSaveFailed(reason: .saveFailedOrCancelled))
            return .cancelled
        }
        return .succeeded
    }

    override func close() {
        trace?.record(.documentClosed(sourceRevision: sourceVersion))
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
        canonicalAssetReferences = CanonicalAssetReferences(values: [])
    }

    func updateCanonicalAssetReferences(_ references: CanonicalAssetReferences) {
        guard canonicalAssetReferences != references else { return }
        canonicalAssetReferences = references
        canonicalAssetReferenceUpdates.send(references)
    }

    /// Canonical load path used by serialized `read(from:ofType:)`.
    ///
    /// // REQ-100: `hasCompletedInitialLoad` — not `sourceVersion == 0` — distinguishes the
    /// // very first content installation from a revert. `sourceVersion` is not a reliable
    /// // proxy: a brand-new document saved without any edit reaches Save with sourceVersion
    /// // still 0 (Save does not itself advance it), so a subsequent revert of that same,
    /// // still-at-revision-0 document would have been misclassified as an initial load.
    /// // `fileURL` is not reliable either — NSDocument's own opening machinery may already
    /// // have set it before `read(from:ofType:)` runs even on the very first load.
    private func installLoadedText(_ value: String) {
        closeTypingGroupIfNeeded()
        let isInitialLoad = !hasCompletedInitialLoad && !isRevertingViaAppKit
        hasCompletedInitialLoad = true
        text = value
        // A revision identifies source content for this document's entire lifetime.
        // Loads/reverts therefore advance it just like edits; identities are never reused.
        sourceVersion &+= 1
        activeTracker = nil
        activeTrackingGeneration = nil
        undoManager?.removeAllActions()
        updateChangeCount(.changeCleared)
        let utf16Count = (value as NSString).length
        if isInitialLoad {
            trace?.record(.documentLoaded(utf16Count: utf16Count, sourceRevision: sourceVersion))
        } else {
            trace?.record(.documentReverted(sourceRevision: sourceVersion, utf16Count: utf16Count))
        }
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
