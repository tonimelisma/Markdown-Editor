//
//  LocalImageResolver.swift
//  Markdown Editor
//

import AppKit
import ImageIO
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

nonisolated struct LocalImageDescriptor: Sendable, Equatable {
    let nodeID: MarkdownNodeID
    let sourceVersion: UInt64
    let locationGeneration: UInt64
    let resolvedURL: URL
    let contentType: String
    let pixelWidth: Int
    let pixelHeight: Int
    let thumbnailPNGData: Data
}

/// Bounded off-main local image decode for WYSIWYG display.
///
/// // REQ-081/085/087: PNG/JPEG/GIF/HEIC/HEIF; no remote fetch; no transcode of originals;
/// // originals untouched; version-gated results.
nonisolated enum LocalImageResolver {
    static let maxPixelDimension = 8_192
    static let maxThumbnailEdge: CGFloat = 512
    static let supportedTypes: Set<String> = [
        "public.png", "public.jpeg", "public.gif",
        "public.heic", "public.heif",
        UTType.png.identifier, UTType.jpeg.identifier, UTType.gif.identifier,
        UTType.heic.identifier, UTType.heif.identifier
    ]

    static func resolve(
        destination: String,
        documentURL: URL?,
        nodeID: MarkdownNodeID,
        sourceVersion: UInt64,
        locationGeneration: UInt64
    ) -> Result<LocalImageDescriptor, LocalImageResolveFailure> {
        // Absolute/remote schemes are never fetched.
        if let url = URL(string: destination), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" || scheme == "ftp" {
            return .failure(.remoteURL)
        }
        if destination.lowercased().hasPrefix("//") {
            return .failure(.remoteURL)
        }

        guard let documentURL else {
            return .failure(.missingFile)
        }
        let folder = documentURL.deletingLastPathComponent()
        let resolved = URL(fileURLWithPath: destination, relativeTo: folder).standardizedFileURL

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir), !isDir.boolValue else {
            return .failure(.missingFile)
        }

        let ext = resolved.pathExtension.lowercased()
        let allowedExt: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif"]
        guard allowedExt.contains(ext) else {
            return .failure(.unsupportedType)
        }

        guard let source = CGImageSourceCreateWithURL(resolved as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return .failure(.corrupt)
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as? [CFString: Any] else {
            return .failure(.corrupt)
        }
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0 else { return .failure(.corrupt) }
        if width > maxPixelDimension || height > maxPixelDimension {
            return .failure(.oversizeDimensions(width: width, height: height))
        }

        let uti = CGImageSourceGetType(source).map { $0 as String } ?? ""
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxThumbnailEdge),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return .failure(.decodeFailed)
        }
        // Thumbnail bytes are derived display-only PNG; original file is never rewritten.
        guard let png = cgImagePNGData(cgThumb) else {
            return .failure(.decodeFailed)
        }

        return .success(
            LocalImageDescriptor(
                nodeID: nodeID,
                sourceVersion: sourceVersion,
                locationGeneration: locationGeneration,
                resolvedURL: resolved,
                contentType: uti,
                pixelWidth: width,
                pixelHeight: height,
                thumbnailPNGData: png
            )
        )
    }

    private static func cgImagePNGData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

/// Bounded derived-image cache keyed by source/location/content identity.
@MainActor
final class LocalImageCache {
    private struct Key: Hashable {
        let sourceVersion: UInt64
        let locationGeneration: UInt64
        let urlPath: String
        let nodeID: UInt64
    }

    private var images: [Key: NSImage] = [:]
    private var order: [Key] = []
    private let maxEntries: Int

    init(maxEntries: Int = 64) {
        self.maxEntries = maxEntries
    }

    func image(for descriptor: LocalImageDescriptor) -> NSImage? {
        let key = Key(
            sourceVersion: descriptor.sourceVersion,
            locationGeneration: descriptor.locationGeneration,
            urlPath: descriptor.resolvedURL.path,
            nodeID: descriptor.nodeID.rawValue
        )
        if let existing = images[key] { return existing }
        guard let image = NSImage(data: descriptor.thumbnailPNGData) else { return nil }
        images[key] = image
        order.append(key)
        while order.count > maxEntries {
            let evicted = order.removeFirst()
            images.removeValue(forKey: evicted)
        }
        return image
    }

    func clear() {
        images.removeAll()
        order.removeAll()
    }
}
