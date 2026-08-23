//
//  ImagePlacementModels.swift
//  Markdown Editor
//

import Foundation
import UniformTypeIdentifiers

// REQ-060/069: immutable action identity and terminal outcomes for one placement transaction.

nonisolated struct ImageActionID: Hashable, Sendable {
    let uuid: UUID
    init(_ uuid: UUID = UUID()) { self.uuid = uuid }
}

/// Immutable source-domain target captured before picker or promise work starts.
///
/// // REQ-060; ARC-012: never consult later live editor state for the insertion point.
nonisolated struct ImagePlacementTarget: Sendable, Equatable {
    let sourceSelection: SourceSelection
    let sourceRevision: SourceRevision
    let locationGeneration: UInt64
    let operationID: UUID
}

/// Complete immutable input consumed by one placement transaction.
nonisolated struct ImagePlacementIntent: Sendable {
    let target: ImagePlacementTarget
    let claims: [ImageClaim]
}

nonisolated enum ImagePlacementPhase: Equatable, Sendable {
    case idle
    case accepted
    case receivingPromises
    case awaitingSave
    case staging
    case publishing
    case committing
    case committed
    case cancelled
    case failed
}

nonisolated enum ImageClaim: Sendable {
    case fileURL(URL, providerName: String?, declaredType: UTType?)
    case bitmapData(Data, providerName: String?, declaredType: UTType?)
    case promiseToken(FilePromiseReceiptToken)
}

/// Opaque handle owned by the promise bridge for one drag action.
nonisolated struct FilePromiseReceiptToken: Sendable, Hashable {
    let id: UUID
    init(_ id: UUID = UUID()) { self.id = id }
}

nonisolated struct ImageActionSnapshot: Sendable {
    let id: ImageActionID
    let intent: IntentContext?
    let claims: [ImageClaim]
    let documentURL: URL?
    let documentLocationGeneration: UInt64
    let sourceRevision: SourceRevision
    let selection: SourceSelection
    let operationID: UUID
}

nonisolated struct DocumentParentIdentity: Sendable, Hashable {
    let device: UInt64
    let inode: UInt64
}

nonisolated struct FileIdentity: Sendable, Hashable {
    let device: UInt64
    let inode: UInt64
}

nonisolated struct StagedImageArtifact: Sendable {
    let stagingURL: URL
    let providerName: String?
    let representation: ImageRepresentation
    let sha256Hex: String
    let byteCount: Int
}

nonisolated struct PublishedImage: Sendable, Equatable {
    let filename: String
    let markdown: String
    let destinationURL: URL
    let wasReused: Bool
    let wasCreatedByThisTransaction: Bool
    let identity: FileIdentity?
}

nonisolated enum ImagePlacementError: Error, Equatable, Sendable {
    case busy
    case noDocumentURL
    case saveCancelled
    case saveFailed
    case documentMoved
    case unsafeDestination
    case unsupportedOrCorrupt
    case typeMismatch
    case writeFailed
    case promiseFailed
    case promiseTimedOut
    case nonRegularSource
    case parentChanged
}

extension ImagePlacementError {
    var userMessage: String {
        switch self {
        case .busy:
            return "Wait for the current image action to finish."
        case .noDocumentURL, .saveCancelled:
            return "Save the document before adding images."
        case .saveFailed:
            return "Could not save the document. Images were not added."
        case .documentMoved, .parentChanged:
            return "The document moved while adding images. References were not inserted."
        case .unsafeDestination:
            return "Cannot use the assets/ folder (symlink, alias, or unsafe path)."
        case .unsupportedOrCorrupt:
            return "Unsupported or corrupt image."
        case .typeMismatch:
            return "Image type does not match a supported format."
        case .writeFailed:
            return "Could not write image files. Nothing was inserted."
        case .promiseFailed:
            return "Could not receive promised image files."
        case .promiseTimedOut:
            return "Timed out waiting for promised image files."
        case .nonRegularSource:
            return "Only regular image files can be added."
        }
    }
}
