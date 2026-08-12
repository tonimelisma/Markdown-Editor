//
//  LocalImageResolver.swift
//  Markdown Editor
//

import AppKit
import UniformTypeIdentifiers

nonisolated enum LocalImageResolveFailure: Error, Sendable, Equatable {
    case remoteURL
    case missingFile
    case encodedFileTooLarge
    case unsupportedType
    case corrupt
    case oversizeDimensions(width: Int, height: Int)
    case decodeFailed
    case staleVersion
}

/// Display descriptor — carries a decoded `CGImage` only; never re-encodes file bytes.
///
/// // REQ-081: no PNG/JPEG destination encoder for file-backed display.
nonisolated struct LocalImageDescriptor: @unchecked Sendable, Equatable {
    let nodeID: MarkdownNodeID
    let sourceVersion: UInt64
    let locationGeneration: UInt64
    let resolvedURL: URL
    let contentType: String
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCost: Int
    let fileModificationDate: Date?
    let contentDigest: String
    let cgImage: CGImage
    let fileIdentity: LocalImageDecoder.ImageFileIdentity

    static func == (lhs: LocalImageDescriptor, rhs: LocalImageDescriptor) -> Bool {
        lhs.nodeID == rhs.nodeID
            && lhs.sourceVersion == rhs.sourceVersion
            && lhs.locationGeneration == rhs.locationGeneration
            && lhs.resolvedURL == rhs.resolvedURL
            && lhs.contentType == rhs.contentType
            && lhs.pixelWidth == rhs.pixelWidth
            && lhs.pixelHeight == rhs.pixelHeight
            && lhs.byteCost == rhs.byteCost
            && lhs.fileModificationDate == rhs.fileModificationDate
            && lhs.contentDigest == rhs.contentDigest
            && lhs.fileIdentity == rhs.fileIdentity
            && lhs.cgImage === rhs.cgImage
    }
}

/// Bounded off-main local image decode for WYSIWYG display.
///
/// // REQ-081/085/087: delegates to `LocalImageDecoder` (CGImage, UTI-validated);
/// // originals untouched; no intermediate display PNG/JPEG encode.
nonisolated enum LocalImageResolver {
    static let maxPixelDimension = LocalImageDecoder.maxPixelDimension
    static let maxThumbnailEdge: CGFloat = LocalImageDecoder.maxDisplayEdge
    static let supportedTypes: Set<String> = LocalImageDecoder.allowedUTIs

    static func resolve(
        destination: String,
        documentURL: URL?,
        nodeID: MarkdownNodeID,
        sourceVersion: UInt64,
        locationGeneration: UInt64
    ) -> Result<LocalImageDescriptor, LocalImageResolveFailure> {
        switch LocalImageDecoder.decode(
            destination: destination,
            documentURL: documentURL,
            locationGeneration: locationGeneration
        ) {
        case .failure(let err):
            return .failure(err)
        case .success(let decoded):
            guard let documentURL else { return .failure(.missingFile) }
            let folder = documentURL.deletingLastPathComponent()
            let resolved = URL(fileURLWithPath: destination, relativeTo: folder).standardizedFileURL
            return .success(
                LocalImageDescriptor(
                    nodeID: nodeID,
                    sourceVersion: sourceVersion,
                    locationGeneration: locationGeneration,
                    resolvedURL: resolved,
                    contentType: decoded.contentType,
                    pixelWidth: decoded.pixelWidth,
                    pixelHeight: decoded.pixelHeight,
                    byteCost: decoded.byteCost,
                    fileModificationDate: decoded.fileModificationDate,
                    contentDigest: decoded.contentDigest,
                    cgImage: decoded.cgImage,
                    fileIdentity: decoded.fileIdentity
                )
            )
        }
    }
}

/// Bounded derived-image cache keyed by source/location/content identity.
@MainActor
final class LocalImageCache {
    private let byteCache = LocalImageByteCache()
    weak var trace: (any EditorTraceSink)?

    var totalBytes: Int { byteCache.totalBytes }

    func currentIdentities() -> Set<LocalImageDecoder.ImageFileIdentity> {
        byteCache.identities()
    }

    func image(for identity: LocalImageDecoder.ImageFileIdentity) -> NSImage? {
        byteCache.displayImage(identity: identity)
    }

    func image(for descriptor: LocalImageDescriptor) -> NSImage? {
        if let cached = byteCache.displayImage(
            identity: descriptor.fileIdentity
        ) {
            return cached
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let displayImage = NSImage(
            cgImage: descriptor.cgImage,
            size: NSSize(
                width: CGFloat(descriptor.cgImage.width) / scale,
                height: CGFloat(descriptor.cgImage.height) / scale
            )
        )
        byteCache.store(
            descriptor.cgImage,
            displayImage: displayImage,
            cost: descriptor.byteCost,
            identity: descriptor.fileIdentity
        )
        // REQ-089: privacy-safe cache instrumentation (cost/total only).
        trace?.record(.imageCacheStore(cost: descriptor.byteCost, totalBytes: byteCache.totalBytes))
        return displayImage
    }

    func clear() {
        byteCache.clear()
    }
}
