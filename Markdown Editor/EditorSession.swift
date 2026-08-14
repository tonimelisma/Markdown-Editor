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
    @Published var resolvedImages: [MarkdownNodeID: NSImage] = [:]
    var authoritativeTree: MarkdownTree?
    private(set) var sourceModeState = SourceModeState()
    private(set) var wysiwygModeState = WYSIWYGModeState()
    private(set) var pendingSelectionRestoration: PendingSelectionRestoration?

    let imageCache = LocalImageCache()
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
        performanceSamplerCoordinator: DiagnosticRunCoordinator = .shared
    ) {
        self.trapsOnReconciliationViolation = trapsOnReconciliationViolation
        self.performanceSamplerCoordinator = performanceSamplerCoordinator
        self.parseCoordinator = ParseCoordinator(snapshotIDs: snapshotIDs)
        installPublicationObserver()
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
        imageCache.trace = document.trace
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
            pendingDocumentMutationIntent.recorder.finish(pendingDocumentMutationIntent, orphaned: true)
            self.pendingDocumentMutationIntent = nil
        }
        let pendingIntents = presentationIntents.values
        presentationIntents.removeAll()
        for intent in pendingIntents {
            intent.recorder.finish(intent, orphaned: true)
        }
        cancellables.removeAll()
        performanceSampler?.invalidate()
        performanceSampler = nil
        publicationObserver?.cancel()
        publicationObserver = nil
        updateOrigin.didChange = nil
        imageCache.trace = nil
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
            guard case .accepted(let transaction) = EditorTransactionKernel.reduce(input, state: state),
                  case .modeChange(let acceptedMode) = transaction.effect else {
                intent.recorder.finish(intent, orphaned: true)
                return
            }
            document.closeTypingUndoGroup()
            mode = acceptedMode
            traceModeToggle(toSource: acceptedMode == .source)
            intent.recorder.finish(intent)
            return
        }
        document?.closeTypingUndoGroup()
        mode = newMode
        traceModeToggle(toSource: newMode == .source)
    }

    /// Retains one downstream parse lease for a native source/image mutation. The initial lease
    /// remains owned by the caller until the synchronous document operation returns.
    @discardableResult
    func stageDocumentMutationIntent(_ intent: IntentContext) -> Bool {
        if let previous = pendingDocumentMutationIntent {
            previous.recorder.finish(previous, orphaned: true)
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

    /// // REQ-094; ARC-015: mode state records real editor events, never reconciliation.
    private func noteModeStateMutation() {
        modeStateMutationCount &+= 1
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
        installPresentation(snapshot, tree: tree, provisional: false)
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

    func installPresentation(
        _ snapshot: PresentationSnapshot,
        tree: MarkdownTree?,
        provisional: Bool,
        intent: IntentContext? = nil
    ) {
        if !provisional, let document {
            let input = EditorInput.reconciliation(
                EditorReconciliationInput(
                    sourceRevision: SourceRevision(value: snapshot.sourceRevision.value),
                    locationGeneration: snapshot.locationGeneration,
                    projectionID: snapshot.id,
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
        let previous = presentation
        let sourceSelection: SourceSelection? = {
            guard let previous,
                  let existing = wysiwygModeState.selection,
                  existing.range.revision.snapshotID == previous.id,
                  case .exact(let sourceRange) = previous.coordinateMap.sourceRange(
                    forProjection: existing.range.utf16,
                    affinity: existing.affinity
                  ) else {
                return nil
            }
            return SourceSelection(utf16: sourceRange, affinity: existing.affinity)
        }()
        presentation = snapshot
        if let intent {
            let supersededIntents = presentationIntents.values
            let alreadyLeasedForPresentation = supersededIntents.contains(intent)
            presentationIntents.removeAll()
            for superseded in supersededIntents where superseded != intent {
                superseded.recorder.finish(superseded, orphaned: true)
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
    func editorStateSnapshot(intentID: IntentID = IntentID(rawValue: 0)) -> EditorStateSnapshot {
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

    /// Adapter-facing source/image commit. The document remains the sole mutable owner; this
    /// method exists so coordinators never call `commitSourceMutation` directly.
    @discardableResult
    func commitEditorInput(_ input: EditorInput) -> EditorTransactionCommitResult {
        guard let document else { return .refused(.unavailable) }
        return document.commitEditorInput(input)
    }

    /// Reduces a transient callback such as marked-text update/cancel without mutating source.
    @discardableResult
    func reduceTransientEditorInput(_ input: EditorInput) -> EditorTransactionReduction {
        EditorTransactionKernel.reduce(input, state: editorStateSnapshot())
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
        let semanticInput = EditorSemanticInput(request: request, intentID: intent.id)
        let input: EditorInput
        switch inputRoute {
        case .wysiwygReplacement:
            input = .wysiwygReplacement(semanticInput)
        case .markedText:
            input = .markedText(
                EditorMarkedTextInput(
                    phase: .commit,
                    request: request,
                    intentID: intent.id
                )
            )
        case .checkbox:
            input = .checkbox(semanticInput)
        default:
            input = .semanticCommand(semanticInput)
        }
        let reduction = EditorTransactionKernel.reduce(
            input,
            state: editorStateSnapshot(intentID: intent.id)
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
            let commitInput = EditorInput.sourceReplacement(
                EditorReplacementInput(mutation: edit.sourceMutation, intentID: intent.id)
            )
            switch document.commitEditorInput(commitInput) {
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
