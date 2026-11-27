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
    private var pendingIntent: IntentContext?
    private let snapshotIDs: PresentationSnapshotIDFactory

    init(snapshotIDs: PresentationSnapshotIDFactory) {
        self.snapshotIDs = snapshotIDs
    }

    func cancel() {
        operationGeneration &+= 1
        parseTask?.cancel()
        parseTask = nil
        if let pendingIntent {
            pendingIntent.recorder.finish(pendingIntent, orphaned: true)
            self.pendingIntent = nil
        }
        parseScheduler.cancel()
    }

    func bumpGenerationAndCancel() {
        operationGeneration &+= 1
        parseTask?.cancel()
    }

    func generation() -> UInt64 { operationGeneration }

    /// Component-test seam for delivering a completed parse against a newer coordinator
    /// generation. Unlike `bumpGenerationAndCancel()`, this deliberately leaves the in-flight
    /// owner running so the production stale-result guard is exercised.
    func bumpGenerationWithoutCancellationForTesting() {
        operationGeneration &+= 1
    }

    /// Schedule parse/projection reconciliation for document's current snapshot.
    /// Extracted verbatim from EditorSession.scheduleParse — no behavior change.
    func scheduleParse(session: EditorSession, document: MarkdownDocument, intent: IntentContext? = nil) {
        let snapshot = document.sourceSnapshot()
        operationGeneration &+= 1
        let generation = operationGeneration
        let currentPresentation = session.presentation
        let imageDisplayService = session.imageDisplayService
        let backingScale = session.editorWindow?.backingScaleFactor ?? 2
        let appearance: ImageDisplayAppearance = {
            switch NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua: return .dark
            default: return .light
            }
        }()
        let intent = intent ?? session.intentRecorder.begin(.reconciliation)

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
        guard parseScheduler.submit(request) else {
            if let replaced = pendingIntent {
                replaced.recorder.finish(replaced, orphaned: true)
            }
            pendingIntent = intent
            return
        }
        document.trace?.record(route: .reconciliationScheduled, .reconciliationScheduled(sourceRevision: snapshot.sourceVersion, generation: generation)
        )
        document.trace?.record(route: .parseStarted, .parseStarted(sourceVersion: snapshot.sourceVersion, utf16Count: (snapshot.text as NSString).length)
        )
        let parseProjectionStart = DispatchTime.now().uptimeNanoseconds
        let task = Task.detached(priority: .userInitiated) { [weak session, weak document] in
            // The owning session explicitly retains this context through every async boundary.
            // Any cancelled or stale operation that reaches this defer is a typed orphan.
            var completed = false
            defer { intent.recorder.finish(intent, orphaned: !completed) }
            if Task.isCancelled {
                await MainActor.run {
                    document?.trace?.record(route: .parseCancelled, .parseCancelled(sourceVersion: snapshot.sourceVersion))
                }
                return
            }
            let index = MarkdownSourceIndex(source: snapshot.text, sourceVersion: snapshot.sourceVersion)
            let parseResult = MarkdownParser.parse(
                snapshot.text,
                sourceVersion: snapshot.sourceVersion,
                intent: intent,
                isCancelled: { Task.isCancelled }
            )
            if Task.isCancelled {
                await MainActor.run {
                    document?.trace?.record(route: .parseCancelled, .parseCancelled(sourceVersion: snapshot.sourceVersion))
                }
                return
            }
            guard case .success(let tree) = parseResult else {
                await MainActor.run {
                    guard let session else { return }
                    guard document?.sourceVersion == snapshot.sourceVersion,
                          session.parseCoordinator.generation() == generation else {
                        document?.trace?.record(route: .reconciliationDiscarded, .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: .stale)
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
                    document?.trace?.record(route: .reconciliationDiscarded, .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: .parseFailure)
                    )
                }
                return
            }
            await MainActor.run {
                document?.trace?.record(route: .parseCompleted, .parseCompleted(sourceVersion: snapshot.sourceVersion))
            }
            let model = MarkdownProjectionModel.build(tree: tree, index: index, intent: intent)
            if case .failure = ProjectionOracle.validate(model: model, sourceUTF16Count: (snapshot.text as NSString).length, intent: intent) {
                await MainActor.run {
                    document?.trace?.record(route: .reconciliationDiscarded, .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: .oracleModel)
                    )
                }
                return
            }
            if Task.isCancelled {
                await MainActor.run {
                    document?.trace?.record(route: .parseCancelled, .parseCancelled(sourceVersion: snapshot.sourceVersion))
                }
                return
            }
            let parseProjectionDuration = DispatchTime.now().uptimeNanoseconds &- parseProjectionStart
            let imageResolutionStart = DispatchTime.now().uptimeNanoseconds
            var descriptors: [ImageDisplayDescriptor] = []
            var resolveFailures: [LocalImageResolveFailure] = []
            for attachment in model.attachments {
                if case .image(let destination, _) = attachment.kind {
                    let request = ImageDecodeRequest(
                        destination: destination,
                        documentURL: snapshot.fileURL,
                        nodeID: attachment.nodeID,
                        sourceRevision: snapshot.sourceVersion,
                        locationGeneration: snapshot.locationGeneration,
                        requestGeneration: generation,
                        pixelTarget: Int(MarkdownTypography.maximumReadingMeasure * 2),
                        backingScale: backingScale,
                        appearance: appearance,
                        intent: intent
                    )
                    switch await imageDisplayService.resolve(request) {
                    case .success(let descriptor): descriptors.append(descriptor)
                    case .failure(let reason):
                        resolveFailures.append(reason)
                    }
                }
            }
            let imageResolutionDuration = DispatchTime.now().uptimeNanoseconds &- imageResolutionStart
            guard !Task.isCancelled else {
                await MainActor.run {
                    document?.trace?.record(route: .parseCancelled, .parseCancelled(sourceVersion: snapshot.sourceVersion))
                }
                return
            }
            await MainActor.run {
                guard let session else { return }
                guard !Task.isCancelled,
                      document?.sourceVersion == snapshot.sourceVersion,
                      document?.locationGeneration == snapshot.locationGeneration,
                      session.parseCoordinator.generation() == generation else {
                    document?.trace?.record(route: .reconciliationDiscarded, .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: .identityMismatch)
                    )
                    return
                }
                let authoritative = PresentationSnapshot.from(
                    model: model,
                    id: session.snapshotIDs.make(),
                    locationGeneration: snapshot.locationGeneration,
                    sourceText: snapshot.text
                )
                if !authoritative.isOracleValid {
                    document?.trace?.record(route: .reconciliationDiscarded, .reconciliationDiscarded(sourceRevision: snapshot.sourceVersion, reason: .oracleSnapshot)
                    )
                    return
                }
                session.authoritativeTree = tree
                for reason in resolveFailures {
                    document?.trace?.record(route: .imageResolutionFailed, .imageResolutionFailed(reason: reason))
                }
                document?.updateCanonicalAssetReferences(CanonicalAssetReferences.from(model: model))
                var images: [MarkdownNodeID: NSImage] = [:]
                for desc in descriptors {
                    images[desc.nodeID] = desc.nsImage(backingScale: backingScale)
                }
                session.resolvedImages = images
                for descriptor in descriptors {
                    document?.trace?.record(
                        route: .imageDisplayCacheObserved,
                        .imageDisplayCacheObserved(
                            hit: descriptor.cacheHit,
                            bytesRead: descriptor.bytesRead,
                            decodeCount: descriptor.decodeCount,
                            durationNanos: descriptor.decodeDurationNanos,
                            totalBytes: descriptor.cacheTotalBytes
                        )
                    )
                }
                let imageResolutionTotal = imageResolutionDuration
                let applicationStart = DispatchTime.now().uptimeNanoseconds
                var carried: SourceSelection?
                if let provisional = session.presentation,
                   session.provisionalPresentationID == provisional.id,
                   provisional.sourceRevision == authoritative.sourceRevision,
                   provisional.locationGeneration == authoritative.locationGeneration,
                   !provisional.hasSameContent(as: authoritative) {
                    // COR-71: a local transition disagreed with the pinned authority. Do not
                    // silently replace an editable provisional snapshot; record a fault, make
                    // WYSIWYG unavailable, and rebuild from canonical source in this same
                    // reconciliation turn. Source remains available throughout.
                    document?.trace?.record(route: .presentationRecovered, .presentationRecovered(
                        snapshotID: provisional.id.value,
                        sourceRevision: provisional.sourceRevision.value,
                        reason: .patchUnprovable
                    ))
                    // The caret the user sees is in the provisional snapshot: carry it, through
                    // that snapshot's coordinates, into the authority, or typing goes on being
                    // refused after the recovery.
                    carried = nil // FALSIFY
                    session.presentation = nil
                    session.authoritativeTree = nil
                    session.updateWYSIWYGModeState {
                        $0.availability = .waitingForCurrentProjection(
                            SourceRevision(value: snapshot.sourceVersion)
                        )
                        $0.selection = nil
                    }
                }
                if session.presentation?.sourceRevision.value == authoritative.sourceRevision.value {
                    session.updateOrigin.with(.programmaticPresentation) {
                        session.installPresentation(authoritative, tree: tree, provisional: false, intent: intent, carrying: carried)
                    }
                } else {
                    session.installPresentation(authoritative, tree: tree, provisional: false, intent: intent, carrying: carried)
                }
                let authoritativeApplicationDuration = DispatchTime.now().uptimeNanoseconds &- applicationStart
                session.performanceSampler?.record(.parseProjection, durationNanos: parseProjectionDuration)
                session.performanceSampler?.record(.imageResolution, durationNanos: imageResolutionTotal)
                session.performanceSampler?.record(.authoritativeApplication, durationNanos: authoritativeApplicationDuration)
                document?.trace?.record(route: .reconciliationApplied, .reconciliationApplied(
                        snapshotID: authoritative.id.value,
                        sourceRevision: authoritative.sourceRevision.value,
                        generation: generation,
                        durationNanos: DispatchTime.now().uptimeNanoseconds &- parseProjectionStart
                    )
                )
                completed = true
            }
        }
        parseTask = task
        Task { @MainActor [weak session, weak document, weak self] in
            await task.value
            guard let session, let self else { return }
            if self.parseScheduler.finish(request), let document {
                let nextIntent = self.pendingIntent
                self.pendingIntent = nil
                self.scheduleParse(session: session, document: document, intent: nextIntent)
            }
        }
    }

    func finish(request: LatestParseRequest) -> Bool {
        parseScheduler.finish(request)
    }
}
