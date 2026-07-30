//
//  EditorSession.swift
//  Markdown Editor
//

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

nonisolated enum EditorMode: String, Sendable, Equatable, CaseIterable {
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
    @Published private(set) var presentation: PresentationSnapshot?
    @Published private(set) var resolvedImages: [MarkdownNodeID: NSImage] = [:]
    private(set) var authoritativeTree: MarkdownTree?
    private(set) var sourceModeState = SourceModeState()
    private(set) var wysiwygModeState = WYSIWYGModeState()
    private(set) var pendingSelectionRestoration: PendingSelectionRestoration?

    let imageCache = LocalImageCache()
    let updateOrigin = EditorUpdateOriginScope()
    private let snapshotIDs = PresentationSnapshotIDFactory()

    /// Injected URL opener — defaults to NSWorkspace. Shared so tests can capture opens.
    var openURL: (URL) -> Void = { url in
        NSWorkspace.shared.open(url)
    }

    /// Injected image picker for “Add Image…” (tests inject results).
    var pickImages: (() async -> [URL])?

    private weak var document: MarkdownDocument?
    private var performanceSampler: PerformanceSampler?
    private var parseTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var publicationObserver: AnyCancellable?
    private var operationGeneration: UInt64 = 0

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

    #if DEBUG
    /// Test seam: the suite that provokes a violation on purpose disables the debug trap.
    /// Every other test and every debug run keeps it, so an ARC-015 regression fails
    /// immediately. `assertionFailure` is already a no-op in release, so this exists only
    /// where the assertion does.
    var trapsOnReconciliationViolation = true
    #endif

    private func reportReconciliationViolation(_ kind: ReconciliationViolation) {
        reconciliationViolationCount &+= 1
        document?.trace?.record(.viewReconciliationViolation(kind: kind))
        #if DEBUG
        if trapsOnReconciliationViolation {
            assertionFailure(
                "ARC-015 counterexample: \(kind) during editor-host view reconciliation"
            )
        }
        #endif
    }

    init() {
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
        self.document = document
        performanceSampler = PerformanceSampler(trace: document.trace)
        updateOrigin.didChange = { [weak document] origin in
            document?.trace?.record(.updateOrigin(origin))
        }
        imageCache.trace = document.trace
        cancellables.removeAll()
        document.objectWillChange
            .sink { [weak self] _ in
                // @Published emits before the canonical value changes. Invalidate the
                // old map synchronously so loaded/reverted source is never editable
                // through a presentation carrying the previous content identity.
                MainActor.assumeIsolated {
                    self?.invalidateDerivedState()
                }
                Task { @MainActor in
                    self?.scheduleParse()
                }
            }
            .store(in: &cancellables)
        document.selectionRestorations
            .sink { [weak self] selection in
                self?.requestSelectionRestoration(selection)
            }
            .store(in: &cancellables)
        scheduleParse()
    }

    func recordPerformance(_ metric: PerformanceSampler.Metric, durationNanos: UInt64) {
        performanceSampler?.record(metric, durationNanos: durationNanos)
    }

    private func invalidateDerivedState() {
        operationGeneration &+= 1
        parseTask?.cancel()
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
        document?.closeTypingUndoGroup()
        mode = newMode
        traceModeToggle(toSource: newMode == .source)
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
            document?.trace?.record(
                .availabilityChanged(editable: editableAfter, sourceRevision: document?.sourceVersion ?? 0)
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
    func installProjectionForTesting(_ model: MarkdownProjectionModel, tree: MarkdownTree) {
        operationGeneration &+= 1
        parseTask?.cancel()
        let snapshot = PresentationSnapshot.from(
            model: model,
            id: snapshotIDs.make(),
            locationGeneration: document?.locationGeneration ?? 0,
            sourceText: document?.text ?? ""
        )
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
        document?.trace?.record(.modeToggle(toSource: toSource))
    }

    private func installPresentation(
        _ snapshot: PresentationSnapshot,
        tree: MarkdownTree?,
        provisional: Bool
    ) {
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
        document?.trace?.record(
            .presentationInstalled(
                snapshotID: snapshot.id.value,
                sourceRevision: snapshot.sourceRevision.value,
                provisional: provisional
            )
        )
    }

    func scheduleParse() {
        guard let document else { return }
        let snapshot = document.sourceSnapshot()
        operationGeneration &+= 1
        let generation = operationGeneration
        let currentPresentation = presentation

        // If there is no current matching presentation, mark WYSIWYG unavailable.
        if currentPresentation?.sourceRevision.value != snapshot.sourceVersion
            || currentPresentation?.locationGeneration != snapshot.locationGeneration {
            if currentPresentation == nil
                || currentPresentation?.sourceRevision.value != snapshot.sourceVersion {
                updateWYSIWYGModeState {
                    $0.availability = .waitingForCurrentProjection(SourceRevision(value: snapshot.sourceVersion))
                }
            }
        }

        parseTask?.cancel()
        document.trace?.record(
            .reconciliationScheduled(sourceRevision: snapshot.sourceVersion, generation: generation)
        )
        // REQ-099: recorded here, synchronously alongside reconciliationScheduled, rather than
        // at the top of the detached task below — this is already a MainActor call site, so
        // recording "off-main parse is starting" costs no extra hop on this frequent path.
        document.trace?.record(
            .parseStarted(sourceVersion: snapshot.sourceVersion, utf16Count: (snapshot.text as NSString).length)
        )
        let reconciliationStart = DispatchTime.now().uptimeNanoseconds
        parseTask = Task.detached(priority: .userInitiated) { [weak self] in
            if Task.isCancelled {
                await MainActor.run {
                    self?.document?.trace?.record(.parseCancelled(sourceVersion: snapshot.sourceVersion))
                }
                return
            }
            let index = MarkdownSourceIndex(source: snapshot.text, sourceVersion: snapshot.sourceVersion)
            let parseResult = MarkdownParser.parse(snapshot.text, sourceVersion: snapshot.sourceVersion)
            if Task.isCancelled {
                await MainActor.run {
                    self?.document?.trace?.record(.parseCancelled(sourceVersion: snapshot.sourceVersion))
                }
                return
            }
            guard case .success(let tree) = parseResult else {
                await MainActor.run {
                    guard let self else { return }
                    guard self.document?.sourceVersion == snapshot.sourceVersion,
                          self.operationGeneration == generation else {
                        self.document?.trace?.record(
                            .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: .stale)
                        )
                        return
                    }
                    self.authoritativeTree = nil
                    if self.presentation?.sourceRevision.value != snapshot.sourceVersion {
                        self.presentation = nil
                        self.updateWYSIWYGModeState {
                            $0.availability = .waitingForCurrentProjection(SourceRevision(value: snapshot.sourceVersion))
                            $0.selection = nil
                        }
                    }
                    self.document?.trace?.record(
                        .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: .parseFailure)
                    )
                }
                return
            }
            // REQ-099: the raw parser step itself succeeded — a fact independent of whether the
            // projection model or snapshot it produces later passes oracle validation or is
            // discarded as stale.
            await MainActor.run {
                self?.document?.trace?.record(.parseCompleted(sourceVersion: snapshot.sourceVersion))
            }
            let model = MarkdownProjectionModel.build(tree: tree, index: index)
            if case .failure = ProjectionOracle.validate(model: model, sourceUTF16Count: (snapshot.text as NSString).length) {
                await MainActor.run {
                    self?.document?.trace?.record(
                        .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: .oracleModel)
                    )
                }
                return
            }
            if Task.isCancelled {
                await MainActor.run {
                    self?.document?.trace?.record(.parseCancelled(sourceVersion: snapshot.sourceVersion))
                }
                return
            }

            var descriptors: [LocalImageDescriptor] = []
            for attachment in model.attachments {
                if case .image(let destination, _) = attachment.kind {
                    if case .success(let desc) = LocalImageResolver.resolve(
                        destination: destination,
                        documentURL: snapshot.fileURL,
                        nodeID: attachment.nodeID,
                        sourceVersion: snapshot.sourceVersion,
                        locationGeneration: snapshot.locationGeneration
                    ) {
                        descriptors.append(desc)
                    }
                }
            }

            await MainActor.run {
                guard let self else { return }
                guard self.document?.sourceVersion == snapshot.sourceVersion,
                      self.document?.locationGeneration == snapshot.locationGeneration,
                      self.operationGeneration == generation else {
                    self.document?.trace?.record(
                        .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: .identityMismatch)
                    )
                    return
                }

                let authoritative = PresentationSnapshot.from(
                    model: model,
                    id: self.snapshotIDs.make(),
                    locationGeneration: snapshot.locationGeneration,
                    sourceText: snapshot.text
                )
                if case .failure = ProjectionOracle.validate(snapshot: authoritative) {
                    self.document?.trace?.record(
                        .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: .oracleSnapshot)
                    )
                    return
                }

                self.authoritativeTree = tree
                var images: [MarkdownNodeID: NSImage] = [:]
                for desc in descriptors {
                    if let image = self.imageCache.image(for: desc) {
                        images[desc.nodeID] = image
                    }
                }
                self.resolvedImages = images

                if self.presentation?.sourceRevision.value == authoritative.sourceRevision.value {
                    // Replace provisional with authoritative under programmatic origin semantics.
                    self.updateOrigin.with(.programmaticPresentation) {
                        self.installPresentation(authoritative, tree: tree, provisional: false)
                    }
                } else {
                    self.installPresentation(authoritative, tree: tree, provisional: false)
                }
                let duration = DispatchTime.now().uptimeNanoseconds - reconciliationStart
                self.performanceSampler?.record(.reconciliation, durationNanos: duration)
                self.document?.trace?.record(
                    .reconciliationApplied(
                        snapshotID: authoritative.id.value,
                        sourceRevision: authoritative.sourceRevision.value,
                        generation: generation,
                        durationNanos: duration
                    )
                )
            }
        }
    }

    /// Primary edit entry — returns accepted source+presentation transition or refusal.
    @discardableResult
    func perform(
        _ command: SemanticCommand,
        selection: EditorSelection,
        expectedSourceRevision: SourceRevision,
        grouping groupingOverride: MutationGrouping? = nil
    ) -> EditorEditOutcome {
        guard let document else { return .refused(.unavailable) }
        let snapshot = document.sourceSnapshot()
        let grouping = groupingOverride ?? SemanticEditEngine.defaultGrouping(for: command)
        let request = EditorEditRequest(
            command: command,
            selection: selection,
            expectedSourceRevision: expectedSourceRevision,
            grouping: grouping
        )
        let planningStart = DispatchTime.now().uptimeNanoseconds
        defer { performanceSampler?.record(.keystrokeTranslation, durationNanos: DispatchTime.now().uptimeNanoseconds - planningStart) }
        let outcome = SemanticEditEngine.plan(
            request,
            snapshot: snapshot,
            presentation: presentation,
            tree: authoritativeTree,
            nextSnapshotID: snapshotIDs.make()
        )
        switch outcome {
        case .accepted(let edit):
            if case .projection = selection {
                guard let current = presentation,
                      let transition = edit.presentationTransition,
                      transition.fromSnapshotID == current.id,
                      transition.nextSnapshot.sourceRevision.value == snapshot.sourceVersion &+ 1,
                      transition.nextSnapshot.locationGeneration == snapshot.locationGeneration,
                      transition.selectionAfter.range.revision.snapshotID == transition.nextSnapshot.id,
                      edit.projectionSelectionAfter?.range.revision.snapshotID == transition.nextSnapshot.id
                else {
                    document.trace?.record(.editRefused(category: .invalidPresentationTransition))
                    return .refused(.unprovable)
                }
            }
            document.trace?.record(
                .editRouted(
                    context: mode,
                    groupingTyping: edit.sourceMutation.grouping == .typing,
                    planner: PlannerKind(command)
                )
            )
            switch document.commitSourceMutation(edit.sourceMutation) {
            case .committed:
                updateSourceModeState { $0.selection = edit.sourceSelectionAfter }
                if let transition = edit.presentationTransition {
                    updateOrigin.with(.programmaticPresentation) {
                        installPresentation(transition.nextSnapshot, tree: authoritativeTree, provisional: true)
                        updateWYSIWYGModeState {
                            $0.selection = edit.projectionSelectionAfter ?? transition.selectionAfter
                        }
                    }
                    document.trace?.record(
                        .presentationTransition(
                            from: transition.fromSnapshotID.value,
                            to: transition.nextSnapshot.id.value,
                            sourceRevision: transition.nextSnapshot.sourceRevision.value,
                            durationNanos: DispatchTime.now().uptimeNanoseconds - planningStart
                        )
                    )
                }
                publishSelectionRestoration(edit: edit)
                scheduleParse()
                return .accepted(edit)
            case .refused(let refusal):
                switch refusal {
                case .staleVersion: return .refused(.staleVersion)
                case .invalidRange: return .refused(.invalidRange)
                case .conflict, .contentMismatch: return .refused(.ambiguousSelection)
                }
            }
        case .refused(let refusal):
            document.trace?.record(.editRefused(category: .refusal(refusal)))
            return .refused(refusal)
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

    func addImages() async {
        guard let document else { return }
        // REQ-060/082; ARC-012: capture immutable source-domain intent before async picker work.
        let target: ImagePlacementTarget
        switch mode {
        case .source:
            target = ImagePlacementTarget(
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
                return
            }
            target = ImagePlacementTarget(
                sourceSelection: SourceSelection(utf16: sourceRange, affinity: projectionSelection.affinity),
                sourceRevision: SourceRevision(value: document.sourceVersion),
                locationGeneration: document.locationGeneration,
                operationID: UUID()
            )
        }
        actionRouter?.captureImagePlacementTarget(target)

        let urls: [URL]
        if let pickImages {
            urls = await pickImages()
        } else {
            urls = await Self.presentOpenPanel()
        }
        guard !urls.isEmpty else { return }
        let claims = urls.map { ImageClaim.fileURL($0, providerName: $0.lastPathComponent, declaredType: nil) }
        actionRouter?.handleAddImageClaims(claims)
    }

    private static func presentOpenPanel() async -> [URL] {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.png, .jpeg, .gif, .heic, .heif]
            panel.begin { response in
                if response == .OK {
                    continuation.resume(returning: panel.urls)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}
