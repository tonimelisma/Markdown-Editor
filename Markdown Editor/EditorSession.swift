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
    @Published private(set) var mode: EditorMode = .wysiwyg
    @Published private(set) var presentation: PresentationSnapshot?
    @Published private(set) var authoritativeTree: MarkdownTree?
    @Published private(set) var sourceModeState = SourceModeState()
    @Published private(set) var wysiwygModeState = WYSIWYGModeState()
    @Published private(set) var resolvedImages: [MarkdownNodeID: NSImage] = [:]
    @Published private(set) var pendingSelectionRestoration: PendingSelectionRestoration?

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
    private var parseTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var operationGeneration: UInt64 = 0

    /// Compatibility: projection model view of the current presentation.
    var projection: MarkdownProjectionModel? { presentation?.asProjectionModel }

    /// Compatibility: accepted source version of the current editable presentation.
    var acceptedSourceVersion: UInt64 { presentation?.sourceRevision.value ?? 0 }

    /// Compatibility: authoritative tree from last matching reconciliation.
    var tree: MarkdownTree? { authoritativeTree }

    func attach(document: MarkdownDocument) {
        self.document = document
        imageCache.trace = document.trace
        cancellables.removeAll()
        document.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleParse()
                }
            }
            .store(in: &cancellables)
        scheduleParse()
    }

    func setMode(_ newMode: EditorMode) {
        guard newMode != mode else { return }
        document?.closeTypingUndoGroup()
        mode = newMode
        traceModeToggle(toSource: newMode == .source)
    }

    func updateSourceModeState(_ mutate: (inout SourceModeState) -> Void) {
        var state = sourceModeState
        mutate(&state)
        sourceModeState = state
    }

    func updateWYSIWYGModeState(_ mutate: (inout WYSIWYGModeState) -> Void) {
        var state = wysiwygModeState
        mutate(&state)
        wysiwygModeState = state
    }

    /// Test/hook: install an already-built projection without waiting on the async parse path.
    func installProjectionForTesting(_ model: MarkdownProjectionModel, tree: MarkdownTree) {
        let snapshot = PresentationSnapshot.from(
            model: model,
            id: snapshotIDs.make(),
            locationGeneration: document?.locationGeneration ?? 0
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

    private func traceModeToggle(toSource: Bool) {
        document?.trace?.record(.modeToggle(toSource: toSource))
    }

    private func installPresentation(
        _ snapshot: PresentationSnapshot,
        tree: MarkdownTree?,
        provisional: Bool
    ) {
        presentation = snapshot
        if !provisional {
            authoritativeTree = tree
        }
        updateWYSIWYGModeState { state in
            state.availability = .editable(snapshot.id)
            if let existing = state.selection,
               existing.range.revision.snapshotID == snapshot.id {
                // keep
            } else if let existing = state.selection {
                // Remap selection onto the new snapshot when possible.
                let mapped = snapshot.coordinateMap.projectionRange(
                    forSource: existing.nsRange.length == 0
                        ? NSRange(location: min(existing.nsRange.location, snapshot.sourceUTF16Count), length: 0)
                        : existing.nsRange
                )
                // Existing selection may already be projection-domain; clamp to rendered bounds.
                let length = (snapshot.renderedString as NSString).length
                let loc = min(existing.nsRange.location, length)
                let len = min(existing.nsRange.length, max(0, length - loc))
                state.selection = ProjectionSelection(
                    utf16: NSRange(location: loc, length: len),
                    revision: snapshot.projectionRevision,
                    affinity: existing.affinity
                )
                _ = mapped
            }
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
        parseTask = Task.detached(priority: .userInitiated) { [weak self] in
            if Task.isCancelled { return }
            let index = MarkdownSourceIndex(source: snapshot.text, sourceVersion: snapshot.sourceVersion)
            let parseResult = MarkdownParser.parse(snapshot.text, sourceVersion: snapshot.sourceVersion)
            if Task.isCancelled { return }
            guard case .success(let tree) = parseResult else {
                await MainActor.run {
                    guard let self else { return }
                    guard self.document?.sourceVersion == snapshot.sourceVersion,
                          self.operationGeneration == generation else {
                        self.document?.trace?.record(
                            .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: "stale")
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
                        .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: "parseFailure")
                    )
                }
                return
            }
            let model = MarkdownProjectionModel.build(tree: tree, index: index)
            if case .failure = ProjectionOracle.validate(model: model, sourceUTF16Count: (snapshot.text as NSString).length) {
                await MainActor.run {
                    self?.document?.trace?.record(
                        .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: "oracle")
                    )
                }
                return
            }
            if Task.isCancelled { return }

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
                        .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: "identityMismatch")
                    )
                    return
                }

                let authoritative = PresentationSnapshot.from(
                    model: model,
                    id: self.snapshotIDs.make(),
                    locationGeneration: snapshot.locationGeneration
                )
                if case .failure = ProjectionOracle.validate(snapshot: authoritative) {
                    self.document?.trace?.record(
                        .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: "oracleSnapshot")
                    )
                    return
                }

                let previous = self.presentation
                self.authoritativeTree = tree
                var images: [MarkdownNodeID: NSImage] = [:]
                for desc in descriptors {
                    if let image = self.imageCache.image(for: desc) {
                        images[desc.nodeID] = image
                    }
                }
                self.resolvedImages = images

                if let previous, previous.sourceRevision.value == authoritative.sourceRevision.value {
                    // Replace provisional with authoritative under programmatic origin semantics.
                    self.updateOrigin.with(.programmaticPresentation) {
                        self.installPresentation(authoritative, tree: tree, provisional: false)
                        if let sel = self.wysiwygModeState.selection {
                            let length = (authoritative.renderedString as NSString).length
                            let loc = min(sel.nsRange.location, length)
                            let len = min(sel.nsRange.length, max(0, length - loc))
                            self.updateWYSIWYGModeState {
                                $0.selection = ProjectionSelection(
                                    utf16: NSRange(location: loc, length: len),
                                    revision: authoritative.projectionRevision,
                                    affinity: sel.affinity
                                )
                            }
                        }
                    }
                } else {
                    self.installPresentation(authoritative, tree: tree, provisional: false)
                }
                self.document?.trace?.record(
                    .reconciliationApplied(
                        snapshotID: authoritative.id.value,
                        sourceRevision: authoritative.sourceRevision.value,
                        generation: generation
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
        let outcome = SemanticEditEngine.plan(
            request,
            snapshot: snapshot,
            presentation: presentation,
            tree: authoritativeTree,
            nextSnapshotID: snapshotIDs.make()
        )
        switch outcome {
        case .accepted(let edit):
            document.trace?.record(
                .editRouted(
                    context: mode == .wysiwyg ? "wysiwyg" : "source",
                    groupingTyping: edit.sourceMutation.grouping == .typing,
                    planner: edit.sourceMutation.actionName
                )
            )
            switch document.commitSourceMutation(edit.sourceMutation) {
            case .committed:
                sourceModeState.selection = edit.sourceSelectionAfter
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
                            sourceRevision: transition.nextSnapshot.sourceRevision.value
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
            document.trace?.record(
                .editRefused(category: String(describing: refusal))
            )
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
        let intent: ImagePlacementIntent
        switch mode {
        case .source:
            intent = ImagePlacementIntent(
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
                    forProjection: projectionSelection.nsRange,
                    affinity: projectionSelection.affinity
                  ) else {
                return
            }
            intent = ImagePlacementIntent(
                sourceSelection: SourceSelection(utf16: sourceRange, affinity: projectionSelection.affinity),
                sourceRevision: SourceRevision(value: document.sourceVersion),
                locationGeneration: document.locationGeneration,
                operationID: UUID()
            )
        }
        actionRouter?.captureImagePlacementIntent(intent)

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
