//
//  LocalImageResolver.swift
//  Markdown Editor
//

import AppKit
import UniformTypeIdentifiers

nonisolated enum LocalImageResolveFailure: Error, Sendable, Equatable {
    case remoteURL
    case missingFile
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
    let cgImage: CGImage

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
        switch LocalImageDecoder.decode(destination: destination, documentURL: documentURL) {
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
                    cgImage: decoded.cgImage
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

    func image(for descriptor: LocalImageDescriptor) -> NSImage? {
        if let cached = byteCache.image(
            path: descriptor.resolvedURL.path,
            locationGeneration: descriptor.locationGeneration,
            modification: descriptor.fileModificationDate,
            contentType: descriptor.contentType,
            pixelWidth: descriptor.pixelWidth,
            pixelHeight: descriptor.pixelHeight,
            byteCost: descriptor.byteCost
        ) {
            return NSImage(
                cgImage: cached,
                size: NSSize(width: cached.width, height: cached.height)
            )
        }
        byteCache.store(
            descriptor.cgImage,
            cost: descriptor.byteCost,
            path: descriptor.resolvedURL.path,
            locationGeneration: descriptor.locationGeneration,
            modification: descriptor.fileModificationDate,
            contentType: descriptor.contentType,
            pixelWidth: descriptor.pixelWidth,
            pixelHeight: descriptor.pixelHeight
        )
        // REQ-089: privacy-safe cache instrumentation (cost/total only).
        trace?.record(.imageCacheStore(cost: descriptor.byteCost, totalBytes: byteCache.totalBytes))
        return NSImage(
            cgImage: descriptor.cgImage,
            size: NSSize(width: descriptor.cgImage.width, height: descriptor.cgImage.height)
        )
    }

    func clear() {
        byteCache.clear()
    }
}
