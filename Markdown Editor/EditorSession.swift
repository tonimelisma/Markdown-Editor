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

nonisolated struct ModeViewState: Sendable, Equatable {
    var selection: NSRange
    var scrollOffset: CGPoint
}

/// Window-scoped session owning derived/transient editor state — not serialized source.
///
/// // REQ-052/053/058/083/085/086: WYSIWYG default; persistent dual views; mode toggle never
/// // rewrites source; version-gated parse/projection.
@MainActor
final class EditorSession: ObservableObject {
    @Published private(set) var mode: EditorMode = .wysiwyg
    @Published private(set) var projection: MarkdownProjectionModel?
    @Published private(set) var tree: MarkdownTree?
    @Published private(set) var acceptedSourceVersion: UInt64 = 0
    @Published var sourceViewState = ModeViewState(selection: NSRange(location: 0, length: 0), scrollOffset: .zero)
    @Published var wysiwygViewState = ModeViewState(selection: NSRange(location: 0, length: 0), scrollOffset: .zero)
    @Published private(set) var resolvedImages: [MarkdownNodeID: NSImage] = [:]

    let imageCache = LocalImageCache()

    /// Injected URL opener — defaults to NSWorkspace. Shared so tests can capture opens.
    var openURL: (URL) -> Void = { url in
        NSWorkspace.shared.open(url)
    }

    /// Injected image picker for “Add Image…” (tests inject results).
    var pickImages: (() async -> [URL])?

    private weak var document: MarkdownDocument?
    private var parseTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    func attach(document: MarkdownDocument) {
        self.document = document
        imageCache.trace = document.trace
        cancellables.removeAll()
        document.objectWillChange
            .sink { [weak self] _ in
                // Hop to the main actor explicitly — RunLoop.main is not the MainActor executor
                // under Swift 6 complete concurrency (REQ-088).
                Task { @MainActor in
                    self?.scheduleParse()
                }
            }
            .store(in: &cancellables)
        scheduleParse()
    }

    func setMode(_ newMode: EditorMode) {
        guard newMode != mode else { return }
        // Snapshot current mode state is owned by adapters; switching never touches source.
        mode = newMode
        // REQ-052/086: inactive view applies newest accepted document version on next update.
        // @Published `mode` already notifies observers.
        traceModeToggle(toSource: newMode == .source)
    }

    /// Test/hook: install an already-built projection without waiting on the async parse path.
    func installProjectionForTesting(_ model: MarkdownProjectionModel, tree: MarkdownTree) {
        self.projection = model
        self.tree = tree
        self.acceptedSourceVersion = model.sourceVersion
        imageCache.trace = document?.trace
    }

    private func traceModeToggle(toSource: Bool) {
        document?.trace?.record(.modeToggle(toSource: toSource))
    }

    func scheduleParse() {
        guard let document else { return }
        let snapshot = document.sourceSnapshot()
        parseTask?.cancel()
        parseTask = Task.detached(priority: .userInitiated) { [weak self] in
            if Task.isCancelled { return }
            let index = MarkdownSourceIndex(source: snapshot.text, sourceVersion: snapshot.sourceVersion)
            let parseResult = MarkdownParser.parse(snapshot.text, sourceVersion: snapshot.sourceVersion)
            if Task.isCancelled { return }
            guard case .success(let tree) = parseResult else {
                await MainActor.run {
                    guard let self, self.document?.sourceVersion == snapshot.sourceVersion else { return }
                    self.tree = nil
                    self.projection = nil
                }
                return
            }
            let model = MarkdownProjectionModel.build(tree: tree, index: index)
            if Task.isCancelled { return }

            // Resolve local images off-main.
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
                      self.document?.locationGeneration == snapshot.locationGeneration else {
                    return // stale
                }
                self.tree = tree
                self.projection = model
                self.acceptedSourceVersion = snapshot.sourceVersion
                var images: [MarkdownNodeID: NSImage] = [:]
                for desc in descriptors {
                    if let image = self.imageCache.image(for: desc) {
                        images[desc.nodeID] = image
                    }
                }
                self.resolvedImages = images
            }
        }
    }

    @discardableResult
    func perform(_ command: SemanticCommand, selection: SemanticSelection) -> SemanticEditResult {
        guard let document else { return .refused(.staleVersion) }
        let snapshot = document.sourceSnapshot()
        let result = SemanticEditEngine.apply(
            command: command,
            selection: selection,
            snapshot: snapshot,
            projection: projection,
            tree: tree
        )
        switch result {
        case .transaction(let edit, let post):
            switch document.commitSourceEdit(edit) {
            case .committed:
                document.pendingSelection = post.range
                document.reportActiveSelection(post.range)
                return result
            case .refused(let refusal):
                switch refusal {
                case .staleVersion: return .refused(.staleVersion)
                case .invalidRange: return .refused(.invalidRange)
                case .conflict, .contentMismatch: return .refused(.ambiguousSelection)
                }
            }
        case .refused:
            return result
        }
    }

    /// Window-scoped image action router (REQ-082). Injected by ContentView.
    weak var actionRouter: EditorActionRouter?

    func addImages() async {
        guard let document else { return }
        // REQ-082: capture window-scoped insertion intent before async picker work.
        let domain: EditorCoordinateDomain = mode == .source ? .source : .wysiwyg
        let range = mode == .source ? sourceViewState.selection : wysiwygViewState.selection
        let intent = EditorSelectionIntent(
            domain: domain,
            sourceVersion: document.sourceVersion,
            range: range,
            affinity: .downstream
        )
        actionRouter?.captureImageInsertionIntent(intent)

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
