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
    static let maxDisplayEdge: CGFloat = MarkdownTypography.maximumReadingMeasure * 2
    static let allowedUTIs: Set<String> = [
        UTType.png.identifier,
        UTType.jpeg.identifier,
        UTType.gif.identifier,
        UTType.heic.identifier,
        UTType.heif.identifier,
        "public.png", "public.jpeg", "public.gif", "public.heic", "public.heif"
    ]

    struct ImageFileIdentity: Hashable, Sendable {
        let path: String
        let fileSize: Int64
        let modificationTime: TimeInterval
        let inode: UInt64
        let locationGeneration: UInt64
    }

    struct DecodedImage: Sendable {
        let cgImage: CGImage
        let contentType: String
        let pixelWidth: Int
        let pixelHeight: Int
        let byteCost: Int
        let fileModificationDate: Date?
        /// SHA-256 hex of file bytes — real content identity for the display cache.
        let contentDigest: String
        let fileIdentity: ImageFileIdentity
    }

    static func identity(
        destination: String,
        documentURL: URL?,
        locationGeneration: UInt64
    ) -> Result<ImageFileIdentity, LocalImageResolveFailure> {
        if let url = URL(string: destination), let scheme = url.scheme?.lowercased(),
           ["http", "https", "ftp"].contains(scheme) {
            return .failure(.remoteURL)
        }
        if destination.lowercased().hasPrefix("//") { return .failure(.remoteURL) }
        guard let documentURL else { return .failure(.missingFile) }
        let resolved = URL(fileURLWithPath: destination, relativeTo: documentURL.deletingLastPathComponent()).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir), !isDir.boolValue else {
            return .failure(.missingFile)
        }
        guard ["png", "jpg", "jpeg", "gif", "heic", "heif"].contains(resolved.pathExtension.lowercased()) else {
            return .failure(.unsupportedType)
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let modified = attributes[.modificationDate] as? Date,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else {
            return .failure(.missingFile)
        }
        guard size <= Int64(maxEncodedFileBytes) else { return .failure(.encodedFileTooLarge) }
        return .success(ImageFileIdentity(
            path: resolved.path,
            fileSize: size,
            modificationTime: modified.timeIntervalSinceReferenceDate,
            inode: inode,
            locationGeneration: locationGeneration
        ))
    }

    static func decode(
        destination: String,
        documentURL: URL?,
        identity suppliedIdentity: ImageFileIdentity? = nil,
        locationGeneration: UInt64 = 0
    ) -> Result<DecodedImage, LocalImageResolveFailure> {
        let fileIdentity: ImageFileIdentity
        switch suppliedIdentity.map(Result.success) ?? identity(destination: destination, documentURL: documentURL, locationGeneration: locationGeneration) {
        case .failure(let error): return .failure(error)
        case .success(let value): fileIdentity = value
        }
        let resolved = URL(fileURLWithPath: fileIdentity.path)

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
                contentDigest: contentDigest,
                fileIdentity: fileIdentity
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
        let identity: LocalImageDecoder.ImageFileIdentity
        let displayEdge: Int
    }

    private struct Entry {
        let image: CGImage
        let displayImage: NSImage
        let cost: Int
    }

    private var map: [Key: Entry] = [:]
    private var order: [Key] = []
    private(set) var totalBytes = 0

    func identities() -> Set<LocalImageDecoder.ImageFileIdentity> {
        Set(map.keys.map(\.identity))
    }

    func image(
        identity: LocalImageDecoder.ImageFileIdentity,
        displayEdge: Int = Int(LocalImageDecoder.maxDisplayEdge)
    ) -> CGImage? {
        let key = Key(identity: identity, displayEdge: displayEdge)
        guard let entry = map[key] else { return nil }
        if let idx = order.firstIndex(of: key) {
            order.remove(at: idx)
            order.append(key)
        }
        return entry.image
    }

    func displayImage(
        identity: LocalImageDecoder.ImageFileIdentity,
        displayEdge: Int = Int(LocalImageDecoder.maxDisplayEdge)
    ) -> NSImage? {
        let key = Key(identity: identity, displayEdge: displayEdge)
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
        identity: LocalImageDecoder.ImageFileIdentity,
        displayEdge: Int = Int(LocalImageDecoder.maxDisplayEdge)
    ) {
        let key = Key(identity: identity, displayEdge: displayEdge)
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
