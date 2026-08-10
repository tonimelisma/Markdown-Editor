//
//  LocalImageDecoder.swift
//  Markdown Editor
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Off-main local image decode returning a bounded `CGImage` — no PNG/JPEG re-encode of files.
///
/// // REQ-081/085/087: PNG/JPEG/GIF/HEIC/HEIF; UTI validation; originals untouched.
nonisolated enum LocalImageDecoder {
    static let maxPixelDimension = 8_192
    static let maxEncodedFileBytes = 256 * 1024 * 1024
    static let maxDisplayEdge: CGFloat = 512
    static let allowedUTIs: Set<String> = [
        UTType.png.identifier,
        UTType.jpeg.identifier,
        UTType.gif.identifier,
        UTType.heic.identifier,
        UTType.heif.identifier,
        "public.png", "public.jpeg", "public.gif", "public.heic", "public.heif"
    ]

    struct DecodedImage: Sendable {
        let cgImage: CGImage
        let contentType: String
        let pixelWidth: Int
        let pixelHeight: Int
        let byteCost: Int
        let fileModificationDate: Date?
        /// SHA-256 hex of file bytes — real content identity for the display cache.
        let contentDigest: String
    }

    static func decode(
        destination: String,
        documentURL: URL?
    ) -> Result<DecodedImage, LocalImageResolveFailure> {
        if let url = URL(string: destination), let scheme = url.scheme?.lowercased(),
           ["http", "https", "ftp"].contains(scheme) {
            return .failure(.remoteURL)
        }
        if destination.lowercased().hasPrefix("//") {
            return .failure(.remoteURL)
        }
        guard let documentURL else { return .failure(.missingFile) }
        let folder = documentURL.deletingLastPathComponent()
        let resolved = URL(fileURLWithPath: destination, relativeTo: folder).standardizedFileURL

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir), !isDir.boolValue else {
            return .failure(.missingFile)
        }

        let ext = resolved.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "gif", "heic", "heif"].contains(ext) else {
            return .failure(.unsupportedType)
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path)
        guard let attributes,
              let fileType = attributes[.type] as? FileAttributeType,
              fileType == .typeRegular,
              let fileSize = attributes[.size] as? NSNumber else {
            return .failure(.missingFile)
        }
        guard fileSize.int64Value <= Int64(maxEncodedFileBytes) else {
            return .failure(.encodedFileTooLarge)
        }

        guard let fileData = try? Data(contentsOf: resolved, options: [.mappedIfSafe]) else {
            return .failure(.missingFile)
        }
        WorkLedgerRecorder.add { $0.imageDecodes += 1; $0.fileBytesRead += fileData.count }
        let contentDigest = ImageAssetPolicy.sha256Hex(fileData)

        guard let source = CGImageSourceCreateWithData(
            fileData as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            return .failure(.corrupt)
        }
        let uti = CGImageSourceGetType(source).map { $0 as String } ?? ""
        guard allowedUTIs.contains(uti) else {
            return .failure(.unsupportedType)
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

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDisplayEdge),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return .failure(.decodeFailed)
        }
        let cost = max(cgImage.bytesPerRow * cgImage.height, 1)
        let modDate = (try? resolved.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        return .success(
            DecodedImage(
                cgImage: cgImage,
                contentType: uti,
                pixelWidth: width,
                pixelHeight: height,
                byteCost: cost,
                fileModificationDate: modDate,
                contentDigest: contentDigest
            )
        )
    }
}

/// Content-aware, display-bound, location-aware LRU cache capped at 64 MiB decoded cost.
///
/// // REQ-081: never exceeds 64 MiB.
@MainActor
final class LocalImageByteCache {
    static let maxBytes = 64 * 1024 * 1024

    private struct Key: Hashable {
        let path: String
        let locationGeneration: UInt64
        let modificationTime: TimeInterval
        let displayEdge: Int
        /// SHA-256 of file bytes — metadata alone can collide for same-size replacements.
        let contentDigest: String
    }

    private struct Entry {
        let image: CGImage
        let displayImage: NSImage
        let cost: Int
    }

    private var map: [Key: Entry] = [:]
    private var order: [Key] = []
    private(set) var totalBytes = 0

    func image(
        path: String,
        locationGeneration: UInt64,
        modification: Date?,
        contentDigest: String,
        displayEdge: Int = Int(LocalImageDecoder.maxDisplayEdge)
    ) -> CGImage? {
        let key = Key(
            path: path,
            locationGeneration: locationGeneration,
            modificationTime: modification?.timeIntervalSinceReferenceDate ?? 0,
            displayEdge: displayEdge,
            contentDigest: contentDigest
        )
        guard let entry = map[key] else { return nil }
        if let idx = order.firstIndex(of: key) {
            order.remove(at: idx)
            order.append(key)
        }
        return entry.image
    }

    func displayImage(
        path: String,
        locationGeneration: UInt64,
        modification: Date?,
        contentDigest: String,
        displayEdge: Int = Int(LocalImageDecoder.maxDisplayEdge)
    ) -> NSImage? {
        let key = Key(
            path: path,
            locationGeneration: locationGeneration,
            modificationTime: modification?.timeIntervalSinceReferenceDate ?? 0,
            displayEdge: displayEdge,
            contentDigest: contentDigest
        )
        guard let entry = map[key] else { return nil }
        if let idx = order.firstIndex(of: key) {
            order.remove(at: idx)
            order.append(key)
        }
        return entry.displayImage
    }

    func store(
        _ image: CGImage,
        displayImage: NSImage,
        cost: Int,
        path: String,
        locationGeneration: UInt64,
        modification: Date?,
        contentDigest: String,
        displayEdge: Int = Int(LocalImageDecoder.maxDisplayEdge)
    ) {
        let key = Key(
            path: path,
            locationGeneration: locationGeneration,
            modificationTime: modification?.timeIntervalSinceReferenceDate ?? 0,
            displayEdge: displayEdge,
            contentDigest: contentDigest
        )
        if let old = map[key] {
            totalBytes -= old.cost
            map.removeValue(forKey: key)
            order.removeAll { $0 == key }
        }
        map[key] = Entry(image: image, displayImage: displayImage, cost: cost)
        order.append(key)
        totalBytes += cost
        while totalBytes > Self.maxBytes, let oldest = order.first {
            if let entry = map.removeValue(forKey: oldest) {
                totalBytes -= entry.cost
            }
            order.removeFirst()
        }
    }

    func clear() {
        map.removeAll()
        order.removeAll()
        totalBytes = 0
    }
}
// COR-47: image identity stub - ImageFileIdentity would be here
