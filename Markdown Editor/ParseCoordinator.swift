//
//  ParseCoordinator.swift
//  Markdown Editor
//

import AppKit
import Foundation

/// Off-main parse scheduling owned by EditorSession but extracted so the session
/// is not a god object. The session keeps @Published presentation/mode state;
/// this coordinator owns LatestParseScheduler + Task + generation.
///
/// // REQ-085/111; ARC-006/011: latest-work scheduling, generation guard, no mutex mirror.
@MainActor
final class ParseCoordinator {
    private var parseTask: Task<Void, Never>?
    private let parseScheduler = LatestParseScheduler()
    private var operationGeneration: UInt64 = 0
    private let snapshotIDs: PresentationSnapshotIDFactory

    init(snapshotIDs: PresentationSnapshotIDFactory) {
        self.snapshotIDs = snapshotIDs
    }

    func cancel() {
        parseTask?.cancel()
        parseTask = nil
        parseScheduler.cancel()
    }

    func bumpGenerationAndCancel() {
        operationGeneration &+= 1
        parseTask?.cancel()
    }

    func generation() -> UInt64 { operationGeneration }

    /// Schedule parse/projection reconciliation for document's current snapshot.
    /// Extracted verbatim from EditorSession.scheduleParse — no behavior change.
    func scheduleParse(session: EditorSession, document: MarkdownDocument) {
        let snapshot = document.sourceSnapshot()
        operationGeneration &+= 1
        let generation = operationGeneration
        let currentPresentation = session.presentation
        let cachedImageIdentities = session.imageCache.currentIdentities()

        if currentPresentation?.sourceRevision.value != snapshot.sourceVersion
            || currentPresentation?.locationGeneration != snapshot.locationGeneration {
            if currentPresentation == nil
                || currentPresentation?.sourceRevision.value != snapshot.sourceVersion {
                session.updateWYSIWYGModeState {
                    $0.availability = .waitingForCurrentProjection(SourceRevision(value: snapshot.sourceVersion))
                }
            }
        }

        parseTask?.cancel()
        let request = LatestParseRequest(source: snapshot, operationGeneration: generation)
        guard parseScheduler.submit(request) else { return }
        document.trace?.record(
            .reconciliationScheduled(sourceRevision: snapshot.sourceVersion, generation: generation)
        )
        document.trace?.record(
            .parseStarted(sourceVersion: snapshot.sourceVersion, utf16Count: (snapshot.text as NSString).length)
        )
        let parseProjectionStart = DispatchTime.now().uptimeNanoseconds
        let task = Task.detached(priority: .userInitiated) { [weak session, weak document] in
            await WorkLedgerRecorder.scope(.reconciliation) {
            if Task.isCancelled {
                await MainActor.run {
                    document?.trace?.record(.parseCancelled(sourceVersion: snapshot.sourceVersion))
                }
                return
            }
            let index = MarkdownSourceIndex(source: snapshot.text, sourceVersion: snapshot.sourceVersion)
            let parseResult = MarkdownParser.parse(
                snapshot.text,
                sourceVersion: snapshot.sourceVersion,
                isCancelled: { Task.isCancelled }
            )
            if Task.isCancelled {
                await MainActor.run {
                    document?.trace?.record(.parseCancelled(sourceVersion: snapshot.sourceVersion))
                }
                return
            }
            guard case .success(let tree) = parseResult else {
                await MainActor.run {
                    guard let session else { return }
                    guard document?.sourceVersion == snapshot.sourceVersion,
                          session.parseCoordinator.generation() == generation else {
                        document?.trace?.record(
                            .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: .stale)
                        )
                        return
                    }
                    session.authoritativeTree = nil
                    if session.presentation?.sourceRevision.value != snapshot.sourceVersion {
                        session.presentation = nil
                        session.updateWYSIWYGModeState {
                            $0.availability = .waitingForCurrentProjection(SourceRevision(value: snapshot.sourceVersion))
                            $0.selection = nil
                        }
                    }
                    document?.trace?.record(
                        .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: .parseFailure)
                    )
                }
                return
            }
            await MainActor.run {
                document?.trace?.record(.parseCompleted(sourceVersion: snapshot.sourceVersion))
            }
            let model = MarkdownProjectionModel.build(tree: tree, index: index)
            if case .failure = ProjectionOracle.validate(model: model, sourceUTF16Count: (snapshot.text as NSString).length) {
                await MainActor.run {
                    document?.trace?.record(
                        .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: .oracleModel)
                    )
                }
                return
            }
            if Task.isCancelled {
                await MainActor.run {
                    document?.trace?.record(.parseCancelled(sourceVersion: snapshot.sourceVersion))
                }
                return
            }
            let parseProjectionDuration = DispatchTime.now().uptimeNanoseconds &- parseProjectionStart
            let imageResolutionStart = DispatchTime.now().uptimeNanoseconds
            var descriptors: [LocalImageDescriptor] = []
            var cachedImageNodes: [MarkdownNodeID: LocalImageDecoder.ImageFileIdentity] = [:]
            var resolveFailures: [LocalImageResolveFailure] = []
            for attachment in model.attachments {
                if case .image(let destination, _) = attachment.kind {
                    switch LocalImageDecoder.identity(
                        destination: destination,
                        documentURL: snapshot.fileURL,
                        locationGeneration: snapshot.locationGeneration
                    ) {
                    case .success(let identity) where cachedImageIdentities.contains(identity):
                        cachedImageNodes[attachment.nodeID] = identity
                    case .success:
                        switch LocalImageResolver.resolve(
                            destination: destination,
                            documentURL: snapshot.fileURL,
                            nodeID: attachment.nodeID,
                            sourceVersion: snapshot.sourceVersion,
                            locationGeneration: snapshot.locationGeneration
                        ) {
                        case .success(let desc): descriptors.append(desc)
                        case .failure(let reason): resolveFailures.append(reason)
                        }
                    case .failure(let reason):
                        resolveFailures.append(reason)
                    }
                }
            }
            let imageResolutionDuration = DispatchTime.now().uptimeNanoseconds &- imageResolutionStart
            await MainActor.run {
                guard let session else { return }
                guard document?.sourceVersion == snapshot.sourceVersion,
                      document?.locationGeneration == snapshot.locationGeneration,
                      session.parseCoordinator.generation() == generation else {
                    document?.trace?.record(
                        .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: .identityMismatch)
                    )
                    return
                }
                let authoritative = PresentationSnapshot.from(
                    model: model,
                    id: session.snapshotIDs.make(),
                    locationGeneration: snapshot.locationGeneration,
                    sourceText: snapshot.text
                )
                if case .failure = ProjectionOracle.validate(snapshot: authoritative) {
                    document?.trace?.record(
                        .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: .oracleSnapshot)
                    )
                    return
                }
                session.authoritativeTree = tree
                for reason in resolveFailures {
                    document?.trace?.record(.imageResolutionFailed(reason: reason))
                }
                document?.updateCanonicalAssetReferences(CanonicalAssetReferences.from(model: model))
                let imageCacheLookupStart = DispatchTime.now().uptimeNanoseconds
                var images: [MarkdownNodeID: NSImage] = [:]
                for (nodeID, identity) in cachedImageNodes {
                    if let image = session.imageCache.image(for: identity) {
                        images[nodeID] = image
                    }
                }
                for desc in descriptors {
                    if let image = session.imageCache.image(for: desc) {
                        images[desc.nodeID] = image
                    }
                }
                session.resolvedImages = images
                let imageResolutionTotal = imageResolutionDuration
                    &+ (DispatchTime.now().uptimeNanoseconds &- imageCacheLookupStart)
                let applicationStart = DispatchTime.now().uptimeNanoseconds
                if session.presentation?.sourceRevision.value == authoritative.sourceRevision.value {
                    session.updateOrigin.with(.programmaticPresentation) {
                        session.installPresentation(authoritative, tree: tree, provisional: false)
                    }
                } else {
                    session.installPresentation(authoritative, tree: tree, provisional: false)
                }
                let authoritativeApplicationDuration = DispatchTime.now().uptimeNanoseconds &- applicationStart
                session.performanceSampler?.record(.parseProjection, durationNanos: parseProjectionDuration)
                session.performanceSampler?.record(.imageResolution, durationNanos: imageResolutionTotal)
                session.performanceSampler?.record(.authoritativeApplication, durationNanos: authoritativeApplicationDuration)
                document?.trace?.record(
                    .reconciliationApplied(
                        snapshotID: authoritative.id.value,
                        sourceRevision: authoritative.sourceRevision.value,
                        generation: generation,
                        durationNanos: DispatchTime.now().uptimeNanoseconds &- parseProjectionStart
                    )
                )
            }
            }
        }
        parseTask = task
        Task { @MainActor [weak session, weak document, weak self] in
            await task.value
            guard let session, let self else { return }
            if self.parseScheduler.finish(request), let document {
                self.scheduleParse(session: session, document: document)
            }
        }
    }

    func finish(request: LatestParseRequest) -> Bool {
        parseScheduler.finish(request)
    }
}
