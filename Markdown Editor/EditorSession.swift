//
//  EditorSession.swift
//  Markdown Editor
//

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

nonisolated enum EditorMode: String, Sendable, Equatable, Codable, CaseIterable {
    case wysiwyg
    case source
}

/// One-shot selection restoration keyed by domain and presentation identity.
///
/// // REQ-083/086; ARC-002: window/editor presentation state — never document-owned.
nonisolated struct PendingSelectionRestoration: Sendable, Equatable {
    enum Domain: Sendable, Equatable {
        case source
        case projection(PresentationSnapshot.ID)
    }

    let domain: Domain
    let sourceSelection: SourceSelection
    let projectionSelection: ProjectionSelection?
}

/// Window-scoped session owning derived/transient editor state — not serialized source.
///
/// // REQ-052/053/058/083/085/086/091/093: typed mode state; revisioned presentation; sync edits.
@MainActor
final class EditorSession: ObservableObject {
    // REQ-094; ARC-015: publication follows rendering, not ownership. Only `mode`,
    // `presentation`, and `resolvedImages` are read from a SwiftUI view body and therefore
    // drive reconciliation. The remaining state is session-owned (ARC-002) but unpublished:
    // publishing it would invalidate the view graph for a fact the graph never consumes.
    @Published private(set) var mode: EditorMode = .wysiwyg
    @Published var presentation: PresentationSnapshot?
    /// The snapshot `installPresentation` last installed as provisional, while it is still the
    /// presentation. COR-71's reconciliation check applies only to it: comparing an authoritative
    /// snapshot with another authoritative one is not a check of a local transition.
    private(set) var provisionalPresentationID: PresentationSnapshot.ID?
    @Published var resolvedImages: [MarkdownNodeID: NSImage] = [:]
    var authoritativeTree: MarkdownTree?
    private(set) var sourceModeState = SourceModeState()
    private(set) var wysiwygModeState = WYSIWYGModeState()
    private(set) var pendingSelectionRestoration: PendingSelectionRestoration?

    /// Sole owner of local image identity, decode, coalescing, and decoded-cache state.
    /// // REQ-085; ARC-023: parse and views do not own a second image route.
    let imageDisplayService: ImageDisplayService
    /// Sole owner of intent identities for this editor window.
    let intentRecorder = IntentRecorder()
    private var presentationIntents: [PresentationSnapshot.ID: IntentContext] = [:]
    /// Native source/image mutations stage their owner before the document publishes. The
    /// publication observer consumes this exact context instead of creating a second owner.
    private var pendingDocumentMutationIntent: IntentContext?
    let updateOrigin = EditorUpdateOriginScope()
    let snapshotIDs = PresentationSnapshotIDFactory()

    /// Injected URL opener — defaults to NSWorkspace. Shared so tests can capture opens.
    var openURL: (URL) -> Void = { url in
        NSWorkspace.shared.open(url)
    }

    var imagePicker: (any ImagePicking)?

    private weak var document: MarkdownDocument?
    private let performanceSamplerCoordinator: DiagnosticRunCoordinator
    var performanceSampler: PerformanceSampler?
    let parseCoordinator: ParseCoordinator
    private var cancellables = Set<AnyCancellable>()
    private var publicationObserver: AnyCancellable?
    /// Coalesces the multiple `@Published` emissions produced by one canonical document
    /// mutation. The mutation's staged intent must be consumed by the one resulting parse,
    /// rather than allowing the second property emission to create a fresh reconciliation owner.
    private var pendingDocumentChangeTask: Task<Void, Never>?
    private(set) weak var editorWindow: NSWindow?
    private var backingPropertiesObserver: NSObjectProtocol?

    // MARK: - View reconciliation scope (REQ-094/096; ARC-015)

    /// Depth of the SwiftUI reconciliation currently running over the editor host.
    private(set) var viewReconciliationDepth = 0

    /// Number of mode-state mutations performed. A reconciliation must not advance it.
    private(set) var modeStateMutationCount: UInt64 = 0

    /// Violations observed while reconciling — publications and live-state captures.
    private(set) var reconciliationViolationCount: UInt64 = 0

    /// Brackets one editor-host reconciliation.
    ///
    /// Any publication or mode-state mutation inside the bracket is an ARC-015 counterexample:
    /// it re-dirties the view being reconciled, and because `@Published` invalidates on
    /// assignment rather than on change, the resulting update loop never settles.
    func withViewReconciliation<T>(_ body: () -> T) -> T {
        viewReconciliationDepth += 1
        defer { viewReconciliationDepth -= 1 }
        return body()
    }

    /// Internal test seam: the suites that provoke a violation on purpose disable the debug
    /// trap through the initializer. The default preserves the production Debug proof, while
    /// keeping the API shape identical in Release so the complete test bundle still compiles.
    private let trapsOnReconciliationViolation: Bool

    private func reportReconciliationViolation(_ kind: ReconciliationViolation) {
        reconciliationViolationCount &+= 1
        document?.trace?.record(route: .viewReconciliationViolation, .viewReconciliationViolation(kind: kind))
        #if DEBUG
        if trapsOnReconciliationViolation {
            assertionFailure(
                "ARC-015 counterexample: \(kind) during editor-host view reconciliation"
            )
        }
        #endif
    }

    init(
        trapsOnReconciliationViolation: Bool = true,
        performanceSamplerCoordinator: DiagnosticRunCoordinator = .shared,
        imageDisplayService: ImageDisplayService = ImageDisplayService()
    ) {
        self.trapsOnReconciliationViolation = trapsOnReconciliationViolation
        self.performanceSamplerCoordinator = performanceSamplerCoordinator
        self.imageDisplayService = imageDisplayService
        self.parseCoordinator = ParseCoordinator(snapshotIDs: snapshotIDs)
        installPublicationObserver()
    }

    /// Binds image-scale identity to the window that owns this session. `NSScreen.main` is
    /// ambient and can describe a different document while windows move between displays.
    func bind(editorWindow: NSWindow) {
        // Compared with the scale the scheduled parse decodes images for, not with the previous
        // window's: the first window bound has no previous one, and `nil != 2` re-parsed every
        // document the moment its window appeared, cancelling the opening parse.
        let scaleChanged = Self.needsRescaleParse(
            scheduled: parseCoordinator.scheduledBackingScale,
            window: editorWindow.backingScaleFactor
        )
        if self.editorWindow !== editorWindow {
            if let backingPropertiesObserver {
                NotificationCenter.default.removeObserver(backingPropertiesObserver)
            }
            self.editorWindow = editorWindow
            backingPropertiesObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeBackingPropertiesNotification,
                object: editorWindow,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.document != nil, let window = self.editorWindow,
                          Self.needsRescaleParse(
                            scheduled: self.parseCoordinator.scheduledBackingScale,
                            window: window.backingScaleFactor
                          ) else { return }
                    self.invalidateDerivedState()
                    self.scheduleParse()
                }
            }
        }
        if scaleChanged, document != nil {
            invalidateDerivedState()
            scheduleParse()
        }
    }

    /// Whether images must be decoded again for a window: only when its scale differs from the
    /// one the scheduled parse used. Before any parse there is nothing to redo.
    nonisolated static func needsRescaleParse(scheduled: CGFloat?, window: CGFloat) -> Bool {
        guard let scheduled else { return false }
        return scheduled != window
    }

    private func installPublicationObserver() {
        guard publicationObserver == nil else { return }
        // ObservableObjectPublisher is not isolated; every mutation of this type is main-actor
        // bound, so observing it under `assumeIsolated` is exact rather than optimistic.
        publicationObserver = objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.viewReconciliationDepth > 0 else { return }
                self.reportReconciliationViolation(.publication)
            }
        }
    }

    func attach(document: MarkdownDocument) {
        installPublicationObserver()
        parseCoordinator.cancel()
        performanceSampler?.invalidate()
        self.document = document
        if let diagnosticLog = DiagnosticLog.shared {
            diagnosticLog.installWorkLedgerWriter(on: intentRecorder)
        }
        document.updateCanonicalAssetReferences(CanonicalAssetReferences(values: []))
        performanceSampler = PerformanceSampler(
            trace: document.trace,
            coordinator: performanceSamplerCoordinator
        )
        updateOrigin.didChange = { [weak document] origin in
            document?.trace?.record(route: .updateOrigin, .updateOrigin(origin))
        }
        cancellables.removeAll()
        document.objectWillChange
            .sink { [weak self] _ in
                // @Published emits before the canonical value changes. Invalidate the
                // old map synchronously so loaded/reverted source is never editable
                // through a presentation carrying the previous content identity.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.invalidateDerivedState()
                    self.scheduleDocumentChangeParse()
                }
            }
            .store(in: &cancellables)
        document.selectionRestorations
            .sink { [weak self] selection in
                self?.requestSelectionRestoration(selection)
            }
            .store(in: &cancellables)
        let openIntent = intentRecorder.begin(.documentOpen)
        scheduleParse(intent: openIntent)
    }

    /// Ends the window/session lifetime without retaining the document, sampler, timer, or
    /// Combine subscriptions. Repeated detach is intentionally harmless.
    func detach() {
        pendingDocumentChangeTask?.cancel()
        pendingDocumentChangeTask = nil
        parseCoordinator.cancel()
        if let pendingDocumentMutationIntent {
            pendingDocumentMutationIntent.recorder.finish(pendingDocumentMutationIntent, superseded: true)
            self.pendingDocumentMutationIntent = nil
        }
        let pendingIntents = presentationIntents.values
        presentationIntents.removeAll()
        for intent in pendingIntents {
            intent.recorder.finish(intent, superseded: true)
        }
        cancellables.removeAll()
        performanceSampler?.invalidate()
        performanceSampler = nil
        publicationObserver?.cancel()
        publicationObserver = nil
        if let backingPropertiesObserver {
            NotificationCenter.default.removeObserver(backingPropertiesObserver)
            self.backingPropertiesObserver = nil
        }
        editorWindow = nil
        updateOrigin.didChange = nil
        let imageService = imageDisplayService
        Task { await imageService.clear() }
        document?.updateCanonicalAssetReferences(CanonicalAssetReferences(values: []))
        document = nil
        presentation = nil
        authoritativeTree = nil
        resolvedImages = [:]
    }

    /// Schedule one reconciliation after the synchronous `@Published` burst for a canonical
    /// mutation has settled. `MarkdownDocument.applyReplacement` publishes `text` and
    /// `sourceVersion` separately; both describe one edit and must share its staged intent.
    private func scheduleDocumentChangeParse() {
        guard pendingDocumentChangeTask == nil else { return }
        pendingDocumentChangeTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.pendingDocumentChangeTask = nil
            self.scheduleParse(intent: self.takePendingDocumentMutationIntent())
            // REQ-145: an external reload replaced the text under a caret the user did not move.
            // Put it back, clamped, rather than resetting them to the top of the document.
            if let hint = self.document?.consumeExternalReloadSelectionHint() {
                let clamped = ExternalChangeDomain.preservedSelection(
                    previous: hint,
                    inNewLength: ((self.document?.text ?? "") as NSString).length
                )
                self.requestSelectionRestoration(SourceSelection(utf16: clamped))
            }
        }
    }

    func recordPerformance(_ metric: PerformanceSampler.Metric, durationNanos: UInt64) {
        performanceSampler?.record(metric, durationNanos: durationNanos)
    }

    /// Aggregate samples collected so far, draining them. Reading is what the periodic flush and
    /// the boundary proof both do; nothing here exposes per-keystroke timings.
    func drainPerformanceSummaries() -> [PerformanceSampler.Summary] {
        performanceSampler?.drainSummaries() ?? []
    }

    private func invalidateDerivedState() {
        parseCoordinator.bumpGenerationAndCancel()
        presentation = nil
        authoritativeTree = nil
        resolvedImages = [:]
        updateWYSIWYGModeState {
            $0.availability = .waitingForCurrentProjection(
                SourceRevision(value: document?.sourceVersion ?? 0)
            )
            $0.selection = nil
        }
    }

    func setMode(_ newMode: EditorMode) {
        guard newMode != mode else { return }
        if let document {
            let intent = intentRecorder.begin(.modeTransition)
            let input = EditorInput.modeChange(
                EditorModeInput(mode: newMode, intentID: intent.id)
            )
            let state = editorStateSnapshot(intentID: intent.id)
            guard case .committed(let transaction) = document.commitEditorInput(input, state: state),
                  case .modeChange(let acceptedMode) = transaction.effect else {
                intent.recorder.finish(intent, orphaned: true)
                return
            }
            mode = acceptedMode
            traceModeToggle(toSource: acceptedMode == .source)
            intent.recorder.finish(intent)
            return
        }
        mode = newMode
        traceModeToggle(toSource: newMode == .source)
    }

    /// Retains one downstream parse lease for a native source/image mutation. The initial lease
    /// remains owned by the caller until the synchronous document operation returns.
    @discardableResult
    func stageDocumentMutationIntent(_ intent: IntentContext) -> Bool {
        if let previous = pendingDocumentMutationIntent {
            previous.recorder.finish(previous, superseded: true)
        }
        guard intent.recorder.retain(intent) else { return false }
        pendingDocumentMutationIntent = intent
        return true
    }

    func cancelStagedDocumentMutationIntent(_ intent: IntentContext) {
        guard pendingDocumentMutationIntent == intent else { return }
        pendingDocumentMutationIntent = nil
        intent.recorder.finish(intent, orphaned: true)
    }

    private func takePendingDocumentMutationIntent() -> IntentContext? {
        defer { pendingDocumentMutationIntent = nil }
        return pendingDocumentMutationIntent
    }

    func updateSourceModeState(_ mutate: (inout SourceModeState) -> Void) {
        noteModeStateMutation()
        var state = sourceModeState
        mutate(&state)
        sourceModeState = state
        // REQ-145: the document keeps the last caret so an external reload can restore it. The
        // session owns selection; the document owns the reload, and this is the one value that
        // has to cross between them.
        document?.lastKnownSourceSelection = state.selection.range.utf16
    }

    func updateWYSIWYGModeState(_ mutate: (inout WYSIWYGModeState) -> Void) {
        noteModeStateMutation()
        var state = wysiwygModeState
        func isEditable(_ availability: WYSIWYGAvailability) -> Bool {
            if case .editable = availability { return true }
            return false
        }
        let editableBefore = isEditable(state.availability)
        mutate(&state)
        wysiwygModeState = state
        // REQ-099: "WYSIWYG went read-only and I don't know why" has, until now, had no log
        // line. Record the transition, not the state, and only when editability itself
        // changes — comparing the whole WYSIWYGAvailability enum (as an earlier version of
        // this code did) is wrong: .editable carries a PresentationSnapshot.ID that changes
        // on every ordinary reconciliation while the editor stays editable, and
        // .waitingForCurrentProjection carries a SourceRevision that changes on every
        // keystroke while the editor stays unavailable — either would report a spurious
        // transition on nearly every keystroke.
        let editableAfter = isEditable(state.availability)
        if editableAfter != editableBefore {
            document?.trace?.record(route: .availabilityChanged, .availabilityChanged(editable: editableAfter, sourceRevision: document?.sourceVersion ?? 0)
            )
        }
    }

    /// Captures a native selection or native action identity before a transaction is planned.
    /// This is input capture, not transaction validation: the kernel validates the submitted
    /// selection against this owner state after the capture has completed. Transaction adapters
    /// never call this with a proposed mutation range.
    func captureSelection(_ selection: EditorSelection) {
        switch selection {
        case .source(let value):
            updateSourceModeState { $0.selection = value }
        case .projection(let value):
            updateWYSIWYGModeState { $0.selection = value }
        }
    }

    /// // REQ-094; ARC-015: mode state records real editor events, never reconciliation.
    /// Every change to mode state, published or not: the menu bar's availability reads the
    /// selection, which lives in unpublished mode state (`KeyWindowCommands`).
    let commandStateChanges = PassthroughSubject<Void, Never>()

    private func noteModeStateMutation() {
        modeStateMutationCount &+= 1
        commandStateChanges.send()
        if viewReconciliationDepth > 0 {
            reportReconciliationViolation(.liveStateCapture)
        }
    }

    /// Test/hook: install an already-built projection without waiting on the async parse path.
    ///
    /// // COR-30: this validates through `ProjectionOracle` exactly as `scheduleParse` does.
    /// // Without it, the seam most WYSIWYG tests rely on could install a snapshot the
    /// // production path would have rejected, so those tests proved their behavior against
    /// // state the app can never actually reach.
    func installProjectionForTesting(_ model: MarkdownProjectionModel, tree: MarkdownTree) {
        parseCoordinator.bumpGenerationAndCancel()
        let snapshot = PresentationSnapshot.from(
            model: model,
            id: snapshotIDs.make(),
            locationGeneration: document?.locationGeneration ?? 0,
            sourceText: document?.text ?? ""
        )
        if !snapshot.isOracleValid {
            assertionFailure("installProjectionForTesting was given an oracle-invalid snapshot")
            return
        }
        // This hook deliberately installs an arbitrary immutable fixture, including a future
        // source revision, so component tests can exercise stale/new-snapshot application. It is
        // not the production reconciliation route and therefore does not pass through the live
        // document identity guard.
        installPresentation(snapshot, tree: tree, provisional: false, validateReconciliation: false)
        if wysiwygModeState.selection == nil {
            captureSelection(.projection(
                ProjectionSelection(utf16: NSRange(location: 0, length: 0), revision: snapshot.projectionRevision)
            ))
        }
    }

    /// Test/hook: drop derived projection so pending-selection wait paths can be exercised.
    func clearProjectionForTesting() {
        presentation = nil
        authoritativeTree = nil
        let revision = SourceRevision(value: document?.sourceVersion ?? 0)
        updateWYSIWYGModeState {
            $0.availability = .waitingForCurrentProjection(revision)
            $0.selection = nil
        }
    }

    /// Re-seeds transient selections between process-level benchmark cases so one case cannot
    /// feed a stale range into the next fixture's ordinary source-command route.
    func resetBenchmarkTransientState() {
        updateSourceModeState {
            $0.selection = SourceSelection(
                utf16: NSRange(location: 0, length: 0),
                affinity: .downstream
            )
        }
        wysiwygModeState = WYSIWYGModeState()
        pendingSelectionRestoration = nil
    }

    /// Test hook for the presentation boundary: image resolution is derived state, and tests
    /// need to prove that a same-text authoritative snapshot refreshes an attachment exactly
    /// when its resolved display image changes.
    func installResolvedImagesForTesting(_ images: [MarkdownNodeID: NSImage]) {
        resolvedImages = images
    }

    func consumePendingSelectionRestoration() -> PendingSelectionRestoration? {
        let value = pendingSelectionRestoration
        pendingSelectionRestoration = nil
        return value
    }

    func requestSelectionRestoration(_ selection: SourceSelection) {
        updateSourceModeState { $0.selection = selection }
        guard mode == .wysiwyg,
              let presentation,
              case .exact(let projected) = presentation.coordinateMap.projectionRange(
                forSource: selection.range.utf16,
                affinity: selection.affinity
              ) else {
            pendingSelectionRestoration = PendingSelectionRestoration(
                domain: .source,
                sourceSelection: selection,
                projectionSelection: nil
            )
            return
        }
        let projectionSelection = ProjectionSelection(
            utf16: projected,
            revision: presentation.projectionRevision,
            affinity: selection.affinity
        )
        pendingSelectionRestoration = PendingSelectionRestoration(
            domain: .projection(presentation.id),
            sourceSelection: selection,
            projectionSelection: projectionSelection
        )
    }

    private func traceModeToggle(toSource: Bool) {
        document?.trace?.record(route: .modeToggle, .modeToggle(toSource: toSource))
    }

    /// The WYSIWYG selection in source coordinates, read through the snapshot it was captured
    /// in, or nil when it belongs to no current snapshot.
    func wysiwygSourceSelection() -> SourceSelection? {
        guard let presentation,
              let existing = wysiwygModeState.selection,
              existing.range.revision.snapshotID == presentation.id,
              case .exact(let sourceRange) = presentation.coordinateMap.sourceRange(
                forProjection: existing.range.utf16,
                affinity: existing.affinity
              ) else {
            return nil
        }
        return SourceSelection(utf16: sourceRange, affinity: existing.affinity)
    }

    /// `carrying` is the selection to map into `snapshot` when the presentation it was captured
    /// in is no longer current: a COR-71 recovery clears the provisional snapshot before the
    /// authority is installed, and without it the caret the user can still see owned no
    /// selection, so every keystroke after a recovery was refused (agent-drive run 45943545906).
    func installPresentation(
        _ snapshot: PresentationSnapshot,
        tree: MarkdownTree?,
        provisional: Bool,
        intent: IntentContext? = nil,
        validateReconciliation: Bool = true,
        carrying carried: SourceSelection? = nil
    ) {
        if !provisional, validateReconciliation, let document {
            let input = EditorInput.reconciliation(
                EditorReconciliationInput(
                    sourceRevision: SourceRevision(value: snapshot.sourceRevision.value),
                    locationGeneration: snapshot.locationGeneration,
                    projectionID: snapshot.id,
                    expectedProjectionID: presentation?.id,
                    intentID: intent?.id ?? IntentID(rawValue: 0)
                )
            )
            guard case .accepted = EditorTransactionKernel.reduce(
                input,
                state: editorStateSnapshot(intentID: intent?.id ?? IntentID(rawValue: 0))
            ), document.sourceVersion == snapshot.sourceRevision.value else {
                return
            }
        }
        let sourceSelection = carried ?? wysiwygSourceSelection()
        presentation = snapshot
        provisionalPresentationID = provisional ? snapshot.id : nil
        if let intent {
            let supersededIntents = presentationIntents.values
            let alreadyLeasedForPresentation = supersededIntents.contains(intent)
            presentationIntents.removeAll()
            for superseded in supersededIntents where superseded != intent {
                superseded.recorder.finish(superseded, superseded: true)
            }
            if !alreadyLeasedForPresentation {
                intent.recorder.retain(intent)
            }
            presentationIntents[snapshot.id] = intent
        }
        if !provisional {
            authoritativeTree = tree
        }
        updateWYSIWYGModeState { state in
            state.availability = .editable(snapshot.id)
            if let sourceSelection,
               case .exact(let projected) = snapshot.coordinateMap.projectionRange(
                    forSource: sourceSelection.range.utf16,
                    affinity: sourceSelection.affinity
               ) {
                state.selection = ProjectionSelection(
                    utf16: projected,
                    revision: snapshot.projectionRevision,
                    affinity: sourceSelection.affinity
                )
            } else if state.selection?.range.revision.snapshotID != snapshot.id {
                state.selection = nil
            }
        }
        if mode == .wysiwyg,
           let pendingSelectionRestoration,
           case .source = pendingSelectionRestoration.domain,
           case .exact(let projected) = snapshot.coordinateMap.projectionRange(
                forSource: pendingSelectionRestoration.sourceSelection.range.utf16,
                affinity: pendingSelectionRestoration.sourceSelection.affinity
           ) {
            let projectionSelection = ProjectionSelection(
                utf16: projected,
                revision: snapshot.projectionRevision,
                affinity: pendingSelectionRestoration.sourceSelection.affinity
            )
            self.pendingSelectionRestoration = PendingSelectionRestoration(
                domain: .projection(snapshot.id),
                sourceSelection: pendingSelectionRestoration.sourceSelection,
                projectionSelection: projectionSelection
            )
        }
        document?.trace?.record(route: .presentationInstalled, .presentationInstalled(
                snapshotID: snapshot.id.value,
                sourceRevision: snapshot.sourceRevision.value,
                provisional: provisional
            )
        )
    }

    /// Transfers the context that installed a snapshot to the host adapter exactly once. The
    /// lookup is snapshot-bound, so a late host update cannot borrow a newer operation's owner.
    func takePresentationIntent(for snapshotID: PresentationSnapshot.ID) -> IntentContext? {
        presentationIntents.removeValue(forKey: snapshotID)
    }

    func scheduleParse(intent: IntentContext? = nil) {
        guard let document else { return }
        let context = intent ?? intentRecorder.begin(.reconciliation)
        parseCoordinator.scheduleParse(session: self, document: document, intent: context)
    }

    /// Captures the immutable session/document state consumed by the pure transaction reducer.
    func editorStateSnapshot(
        intentID: IntentID = IntentID(rawValue: 0)
    ) -> EditorStateSnapshot {
        let source = document?.sourceSnapshot() ?? SourceSnapshot(
            text: "",
            sourceVersion: 0,
            locationGeneration: 0,
            fileURL: nil
        )
        return EditorStateSnapshot(
            source: source,
            mode: mode,
            origin: updateOrigin.current,
            sourceSelection: sourceModeState.selection,
            projectionSelection: wysiwygModeState.selection,
            presentation: presentation,
            tree: authoritativeTree,
            intentID: intentID,
            nextPresentationID: snapshotIDs.make()
        )
    }

    /// Adapter-facing source/image commit. The document remains the sole mutable owner.
    @discardableResult
    func commitEditorInput(
        _ input: EditorInput
    ) -> EditorTransactionCommitResult {
        guard let document else { return .refused(.unavailable) }
        return document.commitEditorInput(
            input,
            state: editorStateSnapshot(intentID: input.intentID)
        )
    }

    /// Primary edit entry — returns accepted source+presentation transition or refusal.
    @discardableResult
    func perform(
        _ command: SemanticCommand,
        selection: EditorSelection,
        expectedSourceRevision: SourceRevision,
        grouping groupingOverride: MutationGrouping? = nil,
        intentScope: WorkScope = .acceptedEdit,
        inputRoute: EditorInputRoute = .semanticCommand
    ) -> EditorEditOutcome {
        guard let document else { return .refused(.unavailable) }
        let intent = intentRecorder.begin(intentScope)
        var handedOffToReconciliation = false
        defer {
            if !handedOffToReconciliation {
                intentRecorder.finish(intent)
            }
        }
        let snapshot = document.sourceSnapshot()
        let grouping = groupingOverride ?? SemanticEditEngine.defaultGrouping(for: command)
        let request = EditorEditRequest(
            command: command,
            selection: selection,
            expectedSourceRevision: expectedSourceRevision,
            grouping: grouping
        )
        let editStart = DispatchTime.now().uptimeNanoseconds
        let state = editorStateSnapshot(intentID: intent.id)
        let plannedOutcome: EditorEditOutcome
        let isOrdinaryNativeReplacement = inputRoute == .wysiwygReplacement
            || inputRoute == .markedText
        let isTypingCommand: Bool
        switch command {
        case .insertText, .deleteBackward:
            isTypingCommand = true
        default:
            isTypingCommand = false
        }
        // The complete main-actor cost of one semantic formatting command — planning, reduction,
        // commit and presentation install — because that whole path is what the user waits for.
        //
        // // Deliberately not scoped to `EditorSemanticWorker.sync`: the worker is one component
        // // of the wait, and measuring the component rather than the wait is how a main-actor
        // // block stayed invisible while "parsing is off-main" remained true. Typing is excluded
        // // because `nativeInputCallback` already bounds it; measuring both would double-count
        // // the same keystroke under two budgets.
        defer {
            if !isTypingCommand {
                recordPerformance(
                    .semanticCommand,
                    durationNanos: DispatchTime.now().uptimeNanoseconds &- editStart
                )
            }
        }
        let nativeClassification: ProjectionSelectionClass? = {
            guard isOrdinaryNativeReplacement,
                  isTypingCommand,
                  case .projection(let projectionSelection) = selection,
                  let presentation = state.presentation else { return nil }
            return ProjectionSelectionClassifier.classify(
                selection: projectionSelection.range.utf16,
                affinity: projectionSelection.affinity,
                snapshot: presentation
            )
        }()
        let localClassification: ProjectionSelectionClass? = {
            guard inputRoute == .markedText,
                  case .syntheticInsertion(.atSourceLocation(let location)) = nativeClassification,
                  case .projection(let projectionSelection) = selection,
                  let presentation = state.presentation,
                  case .exact(let sourceRange) = presentation.coordinateMap.sourceRange(
                      forProjection: projectionSelection.range.utf16,
                      affinity: projectionSelection.affinity
                  ),
                  sourceRange == NSRange(location: location, length: 0) else {
                return nativeClassification
            }
            // IME commit is a separately declared local branch in COR-71. A block-end synthetic
            // anchor may still be an exact source insertion point; preserve the ordinary
            // synthetic refusal matrix and use that proof only for the composition transaction.
            return .identityText(sourceRange: sourceRange)
        }()
        if isOrdinaryNativeReplacement,
           case .projection(let projected) = selection,
           isTypingCommand,
           let presentation = state.presentation,
           let classification = localClassification,
           LocalTransitionDomain.classify(classification) != .taskMarker,
           inputRoute == .markedText
            || LocalTransitionDomain.touchesNoBoundary(projected.range.utf16, in: presentation) {
            // COR-71: this route is deliberately synchronous but parser-free. The closed local
            // domain either produces a complete identity transition or refuses before owner
            // mutation; authoritative reconciliation is scheduled only after an accepted edit.
            plannedOutcome = LocalTransitionDomain.plan(
                request,
                snapshot: state.source,
                presentation: presentation,
                tree: state.tree,
                nextSnapshotID: state.nextPresentationID,
                intent: intent,
                classification: classification
            )
        } else {
            plannedOutcome = EditorSemanticWorker.sync(intent: intent) {
                SemanticEditEngine.plan(
                    request,
                    snapshot: state.source,
                    presentation: state.presentation,
                    tree: state.tree,
                    nextSnapshotID: state.nextPresentationID,
                    intent: intent
                )
            }
        }
        let semanticInput = EditorSemanticInput(
            request: request,
            plannedOutcome: plannedOutcome,
            intentID: intent.id
        )
        let input: EditorInput
        switch inputRoute {
        case .wysiwygReplacement:
            input = .wysiwygReplacement(semanticInput)
        case .markedText:
            input = .markedText(
                EditorMarkedTextInput(
                    phase: .commit,
                    request: request,
                    sourceRevision: expectedSourceRevision,
                    projectionID: state.presentation?.id,
                    plannedOutcome: plannedOutcome,
                    intentID: intent.id
                )
            )
        case .checkbox:
            input = .checkbox(semanticInput)
        default:
            input = .semanticCommand(semanticInput)
        }
        var reductionAudit = EditorTransactionReductionAudit()
        let reduction = EditorTransactionKernel.reduce(
            input,
            state: state,
            audit: &reductionAudit
        )
        switch reduction {
        case .accepted(let transaction):
            guard case .edit(let plannedEdit) = transaction.effect else {
                return .refused(.unavailable)
            }
            let edit = plannedEdit.withIntent(intent)
            if case .projection = selection {
                guard let current = presentation,
                      let transition = edit.presentationTransition,
                      transition.fromSnapshotID == current.id,
                      transition.nextSnapshot.sourceRevision.value == snapshot.sourceVersion &+ 1,
                      transition.nextSnapshot.locationGeneration == snapshot.locationGeneration,
                      transition.selectionAfter.range.revision.snapshotID == transition.nextSnapshot.id,
                      edit.projectionSelectionAfter?.range.revision.snapshotID == transition.nextSnapshot.id
                else {
                    document.trace?.record(route: .editRefused, .editRefused(category: .invalidPresentationTransition))
                    return .refused(.unprovable)
                }
            }
            document.trace?.record(route: .editRouted, .editRouted(
                    context: mode,
                    groupingTyping: edit.sourceMutation.grouping == .typing,
                    planner: PlannerKind(command)
                )
            )
            let commitTransaction = AcceptedEditorTransaction(
                route: transaction.route,
                intentID: transaction.intentID,
                request: transaction.request,
                checkboxNodeID: transaction.checkboxNodeID,
                effect: .edit(edit)
            )
            switch document.commitEditorTransaction(
                commitTransaction,
                state: state,
                audit: reductionAudit
            ) {
            case .committed:
                updateSourceModeState { $0.selection = edit.sourceSelectionAfter }
                if let transition = edit.presentationTransition {
                    updateOrigin.with(.programmaticPresentation) {
                        installPresentation(transition.nextSnapshot, tree: authoritativeTree, provisional: true, intent: edit.intent)
                        updateWYSIWYGModeState {
                            $0.selection = edit.projectionSelectionAfter ?? transition.selectionAfter
                        }
                    }
                    document.trace?.record(route: .presentationTransition, .presentationTransition(
                            from: transition.fromSnapshotID.value,
                            to: transition.nextSnapshot.id.value,
                            sourceRevision: transition.nextSnapshot.sourceRevision.value,
                            durationNanos: DispatchTime.now().uptimeNanoseconds &- editStart
                        )
                    )
                }
                publishSelectionRestoration(edit: edit)
                // This commit's `objectWillChange` queued a deferred document-change parse of the
                // same revision. This route schedules that parse itself, so the deferred one would
                // parse it a second time, and when it landed after this one had installed, COR-71's
                // check compared two authoritative snapshots (repeat-smoke 45925262536). It is
                // dropped unless a native mutation staged an intent for it to carry.
                if pendingDocumentMutationIntent == nil {
                    pendingDocumentChangeTask?.cancel()
                    pendingDocumentChangeTask = nil
                }
                scheduleParse(intent: intent)
                handedOffToReconciliation = true
                return .accepted(edit)
            case .refused(let refusal):
                document.trace?.record(route: .editRefused, .editRefused(category: .refusal(refusal.asEditRefusal)))
                return .refused(refusal.asEditRefusal)
            }
        case .refused(let refusal):
            document.trace?.record(route: .editRefused, .editRefused(category: .refusal(refusal.asEditRefusal)))
            return .refused(refusal.asEditRefusal)
        }
    }

    private func publishSelectionRestoration(edit: AcceptedEdit) {
        if let projection = edit.projectionSelectionAfter,
           let transition = edit.presentationTransition {
            pendingSelectionRestoration = PendingSelectionRestoration(
                domain: .projection(transition.nextSnapshot.id),
                sourceSelection: edit.sourceSelectionAfter,
                projectionSelection: projection
            )
        } else {
            pendingSelectionRestoration = PendingSelectionRestoration(
                domain: .source,
                sourceSelection: edit.sourceSelectionAfter,
                projectionSelection: nil
            )
        }
    }

    /// Window-scoped image action router (REQ-082). Injected by ContentView.
    weak var actionRouter: EditorActionRouter?

    var canAddImages: Bool {
        imagePlacementTarget() != nil
    }

    func addImages() async {
        // REQ-060/082; ARC-012: capture immutable source-domain intent before async picker work.
        let intent = intentRecorder.begin(.acceptedEdit)
        guard let target = imagePlacementTarget() else {
            intent.recorder.finish(intent)
            return
        }
        actionRouter?.captureImagePlacementTarget(target)

        guard let imagePicker else {
            intent.recorder.finish(intent)
            return
        }
        let urls = await imagePicker.pickImages()
        guard !urls.isEmpty else {
            intent.recorder.finish(intent)
            return
        }
        let claims = urls.map { ImageClaim.fileURL($0, providerName: $0.lastPathComponent, declaredType: nil) }
        guard let actionRouter else {
            intent.recorder.finish(intent)
            return
        }
        actionRouter.handleAddImageClaims(claims, intentContext: intent)
    }

    private func imagePlacementTarget() -> ImagePlacementTarget? {
        guard let document else { return nil }
        switch mode {
        case .source:
            return ImagePlacementTarget(
                sourceSelection: sourceModeState.selection,
                sourceRevision: SourceRevision(value: document.sourceVersion),
                locationGeneration: document.locationGeneration,
                operationID: UUID()
            )
        case .wysiwyg:
            guard let presentation,
                  case .editable(let id) = wysiwygModeState.availability,
                  id == presentation.id,
                  let projectionSelection = wysiwygModeState.selection,
                  projectionSelection.range.revision.snapshotID == presentation.id,
                  case .exact(let sourceRange) = presentation.coordinateMap.sourceRange(
                    forProjection: projectionSelection.range.utf16,
                    affinity: projectionSelection.affinity
                  ) else {
                return nil
            }
            return ImagePlacementTarget(
                sourceSelection: SourceSelection(utf16: sourceRange, affinity: projectionSelection.affinity),
                sourceRevision: SourceRevision(value: document.sourceVersion),
                locationGeneration: document.locationGeneration,
                operationID: UUID()
            )
        }
    }

}
