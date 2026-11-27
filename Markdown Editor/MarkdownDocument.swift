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
    weak var currentPrintView: NSTextView?
    // MARK: - Readable types
    // Hardcoded UTI string: class getters are called from AppKit autosave on arbitrary
    // executor contexts under Swift 6; avoid any cross-type static access here.

    nonisolated override class var readableTypes: [String] {
        [MarkdownContentType.identifier]
    }

    nonisolated override class var writableTypes: [String] {
        [MarkdownContentType.identifier]
    }

    nonisolated override class func isNativeType(_ type: String) -> Bool {
        type == MarkdownContentType.identifier
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
    /// Last source-domain selection committed through the document seam. It is used only to
    /// close a typing group when the next input was captured after a caret move, keeping that
    /// boundary in the document owner rather than in either AppKit adapter.
    private var lastCommittedSourceSelection: SourceSelection?
    /// AppKit records marked-text changes on the document undo manager. The document owns the
    /// short-lived group opened for that native transient route.
    private var markedTextGroupOpen = false
    /// Whether the open typing group holds an edit. AppKit counts a change only when a group
    /// closes, and nothing closes a typing group while typing goes on.
    private var typingGroupHasChanges = false
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
        trace?.record(route: .documentOpened, .documentOpened(utf16Count: (text as NSString).length))
        let contentView = ContentView(document: self)
        let hosting = NSHostingController(rootView: contentView)
        // REQ-104: the screenshot verification may make the window taller so one capture can
        // show every semantic construct at once. Width stays at the default, because the default
        // width is what the reading measure and the untruncated toolbar are reviewed against.
        var contentSize = Self.defaultContentSize(visibleFrame: NSScreen.main?.visibleFrame)
        if let height = MarkdownAppDelegate.smokeWindowHeight { contentSize.height = height }
        // The window is created with its final style and size, and only then given its content.
        // Each change to a window's frame lays out the whole tree again — SwiftUI's render, both
        // editors, the toolbar — so a window made by NSWindow(contentViewController:), restyled and
        // then resized was laid out three times (720×560, 720×592, 720×560; CI 45937955461). On
        // a CI runner one of those extra passes was 8 of the first window's 24–28 main-thread
        // samples (repeat-smoke 45923942236). Now every resize lands on the final size.
        hosting.view.frame = NSRect(origin: .zero, size: contentSize)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // The window controller owns the window; AppKit must not also release it when it closes.
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        window.contentMinSize = Self.minimumContentSize
        let controller = NSWindowController(window: window)
        controller.contentViewController = hosting
        controller.shouldCascadeWindows = true
        if !MarkdownAppDelegate.isSmokeRun {
            let name = Self.frameAutosaveName
            // Restore what AppKit saved, but not a size no reader chose: the owner's copy opened
            // stamp-sized, from a frame a unit test had shrunk to the minimum and AppKit saved
            // into the app's own defaults. Saving the corrected frame back means the controller,
            // which applies the saved frame again, cannot put the small one back.
            if window.setFrameUsingName(name) {
                let restored = window.contentRect(forFrameRect: window.frame).size
                if restored.width < Self.smallestRestorableContentSize.width
                    || restored.height < Self.smallestRestorableContentSize.height {
                    window.setContentSize(contentSize)
                    window.center()
                    window.saveFrame(usingName: name)
                }
            }
            controller.windowFrameAutosaveName = name
        }
        window.tabbingIdentifier = "MarkdownDocument"
        window.tabbingMode = .preferred
        addWindowController(controller)
    }

    /// The size a new document window opens at: wide enough for the whole toolbar beside the
    /// title and a full reading measure, tall enough to read a page, and never larger than the
    /// screen allows. It was 720×560, at which the toolbar already overflowed.
    nonisolated static func defaultContentSize(visibleFrame: NSRect?) -> NSSize {
        let wanted = NSSize(width: 880, height: 720)
        guard let visible = visibleFrame else { return wanted }
        return NSSize(
            width: max(minimumContentSize.width, min(wanted.width, visible.width - 80)),
            height: max(minimumContentSize.height, min(wanted.height, visible.height - 120))
        )
    }

    nonisolated static let minimumContentSize = NSSize(width: 420, height: 300)

    /// A saved frame smaller than this is a leftover, not a choice, and is not restored.
    nonisolated static let smallestRestorableContentSize = NSSize(width: 480, height: 340)

    /// The name AppKit saves the window frame under, in the app's defaults. Unit tests run inside
    /// the app and share those defaults, so they save under their own name: a test that shrank a
    /// window to its minimum size left the real app opening stamp-sized (owner, 2026-11-27).
    nonisolated static var frameAutosaveName: String {
        MarkdownAppDelegate.isRunningUnitTests ? "MarkdownDocumentWindow.tests" : "MarkdownDocumentWindow"
    }

    override func printOperation(
        withSettings printSettings: [NSPrintInfo.AttributeKey: Any]
    ) throws -> NSPrintOperation {
        guard let currentPrintView else {
            throw NSError(
                domain: "MarkdownEditor.Print",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No visible editor is available to print"]
            )
        }
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        return NSPrintOperation(view: currentPrintView, printInfo: printInfo)
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
        // A save is a boundary in the history: the typing before it is counted now, so the
        // saved point is after it, and the group closing later cannot mark the document edited.
        closeTypingGroupIfNeeded()
        let utf16Count = (text as NSString).length
        trace?.record(route: .documentSaveStarted, .documentSaveStarted(utf16Count: utf16Count))
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
            // With another app's write unresolved, AppKit stops the save to ask the person: the
            // app's designed outcome (REQ-146), recorded as such rather than as an error.
            trace?.record(route: .documentSaveFailed, .documentSaveFailed(
                reason: hasUnresolvedExternalChange ? .awaitingConflictDecision : .saveFailedOrCancelled
            ))
        } else {
            // REQ-146: writing the buffer to the file is the user resolving the disagreement in
            // favour of their own edits, which is the only way it resolves without a revert.
            hasUnresolvedExternalChange = false
            let durationNanos = DispatchTime.now().uptimeNanoseconds - startUptimeNanos
            trace?.record(route: .documentSaveSucceeded, .documentSaveSucceeded(
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
                self.trace?.record(route: .documentLoadFailed, .documentLoadFailed(reason: .fileUnreadable))
            }
            throw error
        }
    }

    // MARK: - External file changes (REQ-145–149)

    /// True while the file on disk and this buffer are known to disagree.
    ///
    /// // Set when an external write arrives against unsaved changes; cleared by a save or a
    /// // revert, both of which end the disagreement. Nothing resolves it automatically: the
    /// // product ranks preservation above convenience, and choosing a winner without being asked
    /// // discards someone's work.
    @Published private(set) var hasUnresolvedExternalChange = false

    /// Edited also while a typing group holds edits AppKit has not counted yet. After a sentence
    /// typed since the last save the document read as clean: an external write was adopted over
    /// the sentence (tour 45968755636), and closing the window would not have asked to save.
    override var isDocumentEdited: Bool {
        super.isDocumentEdited || typingGroupHasChanges
    }

    /// Applies an external file event. The single route; the `NSFilePresenter` callbacks below
    /// are one line each so the behaviour lives here, where it is directly testable.
    ///
    /// // REQ-145–149; ARC-027. Returns the outcome so callers and tests observe the same value
    /// // the diagnostic records.
    @discardableResult
    func applyExternalChange(_ event: ExternalFileEvent) -> ExternalChangeOutcome {
        let local: LocalEditState = isDocumentEdited ? .dirty : .clean
        let outcome = ExternalChangeDomain.outcome(for: event, local: local)

        switch outcome {
        case .reloadPreservingSelection:
            // Nothing unsaved to lose. Adopt the file; the session restores each editor's caret
            // from `externalReloadSelectionHint` after the new source is installed.
            if let url = fileURL {
                externalReloadSelectionHint = ExternalChangeDomain.preservedSelection(
                    previous: lastKnownSourceSelection,
                    inNewLength: (text as NSString).length
                )
                do {
                    try revert(toContentsOf: url, ofType: fileType ?? MarkdownContentType.identifier)
                } catch {
                    // The file became unreadable between the notification and the read. Keeping
                    // the buffer is the conservative half of the matrix, so take it.
                    externalReloadSelectionHint = nil
                    hasUnresolvedExternalChange = true
                }
            }
        case .retainLocalEditsAsConflicted:
            hasUnresolvedExternalChange = true
        case .retainContentAfterDeletion:
            // The buffer is now the only copy, so it must be treated as unsaved work rather than
            // as a clean document that could be discarded on close without asking.
            hasUnresolvedExternalChange = true
            updateChangeCount(.changeDone)
        case .followMove:
            // `fileURL` has already been updated by AppKit; the observer on it advances
            // `locationGeneration`, which is what re-resolves relative `assets/…` references.
            break
        }

        trace?.record(route: .externalFileChange, .externalFileChange(
            event: event,
            local: local,
            outcome: outcome,
            sourceRevision: sourceVersion
        ))
        return outcome
    }

    /// The caret to restore after an external reload, consumed by `EditorSession`.
    private(set) var externalReloadSelectionHint: NSRange?

    func consumeExternalReloadSelectionHint() -> NSRange? {
        defer { externalReloadSelectionHint = nil }
        return externalReloadSelectionHint
    }

    /// The most recent source caret, recorded so a reload can put it back.
    var lastKnownSourceSelection: NSRange = NSRange(location: 0, length: 0)

    override func presentedItemDidChange() {
        // AppKit delivers this off the main actor, and delivers it for this application's own
        // writes as well as for foreign ones.
        Task { @MainActor [weak self] in
            guard let self, let url = self.fileURL else { return }
            guard FileManager.default.fileExists(atPath: url.path) else {
                self.applyExternalChange(.deleted)
                return
            }
            let onDisk = try? String(contentsOf: url, encoding: .utf8)
            guard ExternalChangeDomain.isForeignContentChange(onDisk: onDisk, buffer: self.text) else {
                return
            }
            self.applyExternalChange(.contentsChanged)
        }
    }

    override func presentedItemDidMove(to newURL: URL) {
        super.presentedItemDidMove(to: newURL)
        Task { @MainActor [weak self] in
            self?.applyExternalChange(.moved)
        }
    }

    nonisolated override func accommodatePresentedItemDeletion(
        completionHandler: @escaping @Sendable ((any Error)?) -> Void
    ) {
        Task { @MainActor [weak self] in
            self?.applyExternalChange(.deleted)
            completionHandler(nil)
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
                self.trace?.record(route: .documentLoadFailed, .documentLoadFailed(reason: .invalidUTF8))
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

    func noteTrackedEdit(edited: NSRange, changeInLength: Int) {
        guard var tracker = activeTracker else { return }
        tracker.applyEdit(edited: edited, changeInLength: changeInLength)
        activeTracker = tracker
    }

    var documentUndoManager: UndoManager? { undoManager }

    /// Main-actor application seam for every canonical document input. Reduction is pure; this
    /// method alone performs source replacement, history registration, and diagnostic emission.
    @discardableResult
    func commitEditorInput(_ input: EditorInput) -> EditorTransactionCommitResult {
        let state = EditorStateSnapshot(
            source: sourceSnapshot(),
            sourceSelection: SourceSelection(utf16: NSRange(location: 0, length: 0)),
            intentID: input.intentID
        )
        return commitEditorInput(input, state: state)
    }

    /// Applies a reduction against the caller's immutable session snapshot. The overload is the
    /// production route: a document never reconstructs selection or presentation identity from
    /// the proposed mutation, so a stale adapter cannot make its own input appear current.
    @discardableResult
    func commitEditorInput(
        _ input: EditorInput,
        state: EditorStateSnapshot
    ) -> EditorTransactionCommitResult {
        // The reducer consumes an immutable snapshot, but the document is the live canonical
        // owner. A caller cannot make a stale snapshot current by supplying matching input data.
        let liveSource = sourceSnapshot()
        guard liveSource.text == state.source.text,
              liveSource.sourceVersion == state.source.sourceVersion,
              liveSource.locationGeneration == state.source.locationGeneration,
              liveSource.fileURL == state.source.fileURL else {
            trace?.record(route: .editRefused, .editRefused(category: .refusal(.staleVersion)))
            return .refused(.staleVersion)
        }
        var audit = EditorTransactionReductionAudit()
        switch EditorTransactionKernel.reduce(input, state: state, audit: &audit) {
        case .refused(let refusal):
            var recorded = false
            if case .sourceReplacement(let value) = input {
                trace?.record(route: .mutationRefused, .mutationRefused(id: value.mutation.id, reason: refusal.asSourceRefusal))
                recorded = true
            } else if case .imageReference(let value) = input {
                trace?.record(route: .mutationRefused, .mutationRefused(id: value.mutation.id, reason: refusal.asSourceRefusal))
                recorded = true
            }
            if case .undoRedo(let history) = input {
                trace?.record(route: .historyRefused, .historyRefused(direction: history.direction, reason: refusal.asSourceRefusal))
                recorded = true
            }
            if !recorded {
                trace?.record(route: .editRefused, .editRefused(category: .refusal(refusal.asEditRefusal)))
            }
            return .refused(refusal)
        case .accepted(let transaction):
            return commitEditorTransaction(transaction, state: state, audit: audit)
        }
    }

    /// Applies a transaction already reduced against the supplied immutable state. Session-owned
    /// semantic routes use this overload so planning and application share exactly one kernel
    /// reduction; the document still revalidates the live source identity before mutation.
    @discardableResult
    func commitEditorTransaction(
        _ transaction: AcceptedEditorTransaction,
        state: EditorStateSnapshot,
        audit: EditorTransactionReductionAudit? = nil
    ) -> EditorTransactionCommitResult {
        let liveSource = sourceSnapshot()
        guard liveSource.text == state.source.text,
              liveSource.sourceVersion == state.source.sourceVersion,
              liveSource.locationGeneration == state.source.locationGeneration,
              liveSource.fileURL == state.source.fileURL else {
            trace?.record(route: .editRefused, .editRefused(category: .refusal(.staleVersion)))
            return .refused(.staleVersion)
        }
        guard audit?.count ?? 1 == 1 else {
            trace?.record(route: .editRefused, .editRefused(category: .refusal(.ambiguousSelection)))
            return .refused(.invalidIdentity)
        }
        if let refusal = EditorTransactionKernel.validateAcceptedTransaction(transaction, state: state) {
            switch transaction.effect {
            case .edit(let edit):
                trace?.record(route: .mutationRefused, .mutationRefused(
                    id: edit.sourceMutation.id,
                    reason: refusal.asSourceRefusal
                ))
            case .history(let history):
                trace?.record(route: .historyRefused, .historyRefused(
                    direction: history.direction,
                    reason: refusal.asSourceRefusal
                ))
            default:
                trace?.record(route: .editRefused, .editRefused(
                    category: .refusal(refusal.asEditRefusal)
                ))
            }
            return .refused(refusal)
        }
        switch transaction.effect {
            case .edit(let edit):
                closeMarkedTextGroupIfNeeded()
                if lastCommittedSourceSelection != edit.sourceMutation.selectionBefore {
                    closeTypingGroupIfNeeded()
                }
                lastCommittedSourceSelection = edit.sourceSelectionAfter
                applyCommittedMutation(edit.sourceMutation)
                return .committed(transaction)
            case .history(let history):
                return applyHistoryPatchAfterReduction(history.patch, direction: history.direction, transaction: transaction)
            case .markedText(let phase):
                switch phase {
                case .update:
                    beginMarkedTextGroupIfNeeded()
                case .cancel:
                    closeMarkedTextGroupIfNeeded()
                case .commit:
                    closeMarkedTextGroupIfNeeded()
                }
                return .committed(transaction)
            case .modeChange:
                closeMarkedTextGroupIfNeeded()
                closeTypingGroupIfNeeded()
                return .committed(transaction)
            case .reconciliation:
                return .committed(transaction)
        }
    }

    private func applyCommittedMutation(_ mutation: SourceMutation) {
        trace?.record(route: .mutationRequested, .mutationRequested(
                id: mutation.id,
                revision: mutation.expectedRevision,
                location: mutation.range.location,
                length: mutation.range.length,
                replacementLength: (mutation.replacement as NSString).length
            )
        )

        let replacementUTF16 = (mutation.replacement as NSString).length
        applyReplacement(range: mutation.range, replacement: mutation.replacement)

        let patch = HistoryPatch.fromCommitted(mutation)
        registerHistoryUndo(for: patch, grouping: mutation.grouping)

        trace?.record(route: .mutationCommitted, .mutationCommitted(
                id: mutation.id,
                newRevision: sourceVersion,
                location: mutation.range.location,
                length: mutation.range.length,
                replacementLength: replacementUTF16
            )
        )
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
                trace?.record(route: .documentSaveFailed, .documentSaveFailed(reason: .saveFailedOrCancelled))
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
            trace?.record(route: .documentSaveFailed, .documentSaveFailed(reason: .saveFailedOrCancelled))
            return .cancelled
        }
        return .succeeded
    }

    override func close() {
        trace?.record(route: .documentClosed, .documentClosed(sourceRevision: sourceVersion))
        // A closing document's open typing group is dropped, never ended. Ending it posts the
        // did-close-group notification, NSDocument then updates its change count with synchronous
        // waiting, and that waits on the close activity already in progress: closing a window
        // after typing hung the app for good (agent-drive probe 45972423807, sampled). The
        // history goes with the document, so there is nothing left to count.
        if let token = undoCheckpointObserver {
            notificationCenterForTesting.removeObserver(token)
            undoCheckpointObserver = nil
        }
        typingGroupOpen = false
        typingGroupHasChanges = false
        // COR-89's memos retain one source, tree and snapshot. Correctness does not depend on
        // clearing them — a new key supersedes the entry — but a closed document should not leave
        // megabytes resident.
        AuthoritativePresentationBuilder.releaseMemo()
        MarkdownParser.releaseMemo()
        super.close()
    }

    // MARK: - Testing helpers

    /// Install text without going through file I/O (unit tests).
    func installTextForTesting(_ value: String) {
        undoManager?.groupsByEvent = false
        attachUndoCheckpointObserverIfNeeded()
        closeMarkedTextGroupIfNeeded()
        closeTypingGroupIfNeeded()
        text = value
        sourceVersion = 0
        lastCommittedSourceSelection = nil
        updateChangeCount(.changeCleared)
        undoManager?.removeAllActions()
        canonicalAssetReferences = CanonicalAssetReferences(values: [])
    }

    /// Benchmark-only canonical fixture installation. The process-level driver uses this route
    /// after opening one empty file so corpus text remains owned by `PerformanceCorpus`.
    func installTextForBenchmark(_ value: String) {
        installTextForTesting(value)
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
        // REQ-146: a load or revert makes the buffer equal the file again, which is exactly what
        // an unresolved external change meant.
        hasUnresolvedExternalChange = false
        let utf16Count = (value as NSString).length
        if isInitialLoad {
            trace?.record(route: .documentLoaded, .documentLoaded(utf16Count: utf16Count, sourceRevision: sourceVersion))
        } else {
            trace?.record(route: .documentReverted, .documentReverted(sourceRevision: sourceVersion, utf16Count: utf16Count))
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
        let input = EditorInput.undoRedo(
            EditorHistoryInput(patch: patch, direction: direction)
        )
        switch commitEditorInput(input) {
        case .refused(let refusal):
            return .refused(refusal.asSourceRefusal)
        case .committed(let transaction):
            guard case .history = transaction.effect else { return .refused(.conflict) }
            return .committed(patch.selectionBefore)
        }
    }

    private func applyHistoryPatchAfterReduction(
        _ patch: HistoryPatch,
        direction: HistoryDirection,
        transaction: AcceptedEditorTransaction
    ) -> EditorTransactionCommitResult {

        applyReplacement(
            range: patch.range,
            replacement: patch.before
        )
        lastCommittedSourceSelection = patch.selectionBefore
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

        trace?.record(route: .historyApplied, .historyApplied(
                direction: direction,
                newRevision: sourceVersion,
                location: patch.range.location,
                length: patch.range.length
            )
        )
        return .committed(transaction)
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
            trace?.record(route: .undoRegistered, .undoRegistered(actionNameLength: patch.actionName.count, groupingTyping: false)
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
            typingGroupHasChanges = true
            trace?.record(route: .undoRegistered, .undoRegistered(actionNameLength: patch.actionName.count, groupingTyping: true)
            )
        }
    }

    private func closeTypingGroupIfNeeded() {
        guard typingGroupOpen else { return }
        typingGroupOpen = false
        typingGroupHasChanges = false
        // Only end a group we actually opened — AppKit/checkpoint churn can leave
        // groupingLevel 0 while our flag was still set.
        guard let undoManager, undoManager.groupingLevel > 0 else { return }
        undoManager.endUndoGrouping()
    }

    private func beginMarkedTextGroupIfNeeded() {
        guard !markedTextGroupOpen, let undoManager, undoManager.groupingLevel == 0 else { return }
        undoManager.beginUndoGrouping()
        markedTextGroupOpen = true
    }

    private func closeMarkedTextGroupIfNeeded() {
        guard markedTextGroupOpen else { return }
        markedTextGroupOpen = false
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
