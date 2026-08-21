//
//  ImageDisplayService.swift
//  Markdown Editor
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Appearance is part of display identity even though the current decoder does not tint pixels.
/// Keeping it in the immutable key prevents a future appearance-sensitive decoder from reusing a
/// result from the wrong presentation environment.
nonisolated enum ImageDisplayAppearance: String, Hashable, Sendable {
    case light
    case dark
}

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

/// Stable metadata observed without opening or reading the image.
nonisolated struct FileIdentitySnapshot: Hashable, Sendable {
    let canonicalURL: URL
    let fileSize: Int64
    let modificationTime: TimeInterval
    let device: UInt64
    let inode: UInt64
    let locationGeneration: UInt64
}

/// Everything needed to resolve one image, captured before background work begins.
nonisolated struct ImageDecodeRequest: Sendable {
    let destination: String
    let documentURL: URL?
    let nodeID: MarkdownNodeID
    let sourceRevision: UInt64
    let locationGeneration: UInt64
    let requestGeneration: UInt64
    let pixelTarget: Int
    let backingScale: CGFloat
    let appearance: ImageDisplayAppearance
    let intent: IntentContext?

    init(
        destination: String,
        documentURL: URL?,
        nodeID: MarkdownNodeID,
        sourceRevision: UInt64,
        locationGeneration: UInt64,
        requestGeneration: UInt64,
        pixelTarget: Int,
        backingScale: CGFloat,
        appearance: ImageDisplayAppearance,
        intent: IntentContext? = nil
    ) {
        self.destination = destination
        self.documentURL = documentURL
        self.nodeID = nodeID
        self.sourceRevision = sourceRevision
        self.locationGeneration = locationGeneration
        self.requestGeneration = requestGeneration
        self.pixelTarget = pixelTarget
        self.backingScale = backingScale
        self.appearance = appearance
        self.intent = intent
    }
}

/// Cache identity deliberately contains metadata, not content hashing.
nonisolated struct ImageReferenceKey: Hashable, Sendable {
    let reference: URL
    let fileSize: Int64
    let modificationTime: TimeInterval
    let device: UInt64
    let inode: UInt64
    let locationGeneration: UInt64
    let pixelTarget: Int
    let backingScale: CGFloat
    let appearance: ImageDisplayAppearance

    init(snapshot: FileIdentitySnapshot, request: ImageDecodeRequest) {
        self.reference = snapshot.canonicalURL
        self.fileSize = snapshot.fileSize
        self.modificationTime = snapshot.modificationTime
        self.device = snapshot.device
        self.inode = snapshot.inode
        self.locationGeneration = snapshot.locationGeneration
        self.pixelTarget = request.pixelTarget
        self.backingScale = request.backingScale
        self.appearance = request.appearance
    }
}

/// Decoded display output. It intentionally contains no source bytes or content digest.
nonisolated struct ImageDisplayDescriptor: @unchecked Sendable, Equatable {
    let nodeID: MarkdownNodeID
    let sourceRevision: UInt64
    let locationGeneration: UInt64
    let requestGeneration: UInt64
    let resolvedURL: URL
    let contentType: String
    let pixelWidth: Int
    let pixelHeight: Int
    let displayPixelWidth: Int
    let displayPixelHeight: Int
    let byteCost: Int
    let fileModificationDate: Date?
    let cacheHit: Bool
    let bytesRead: Int
    let decodeCount: Int
    let decodeDurationNanos: UInt64
    let cacheTotalBytes: Int
    let cgImage: CGImage
    let identity: FileIdentitySnapshot

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.nodeID == rhs.nodeID
            && lhs.sourceRevision == rhs.sourceRevision
            && lhs.locationGeneration == rhs.locationGeneration
            && lhs.requestGeneration == rhs.requestGeneration
            && lhs.resolvedURL == rhs.resolvedURL
            && lhs.contentType == rhs.contentType
            && lhs.pixelWidth == rhs.pixelWidth
            && lhs.pixelHeight == rhs.pixelHeight
            && lhs.displayPixelWidth == rhs.displayPixelWidth
            && lhs.displayPixelHeight == rhs.displayPixelHeight
            && lhs.byteCost == rhs.byteCost
            && lhs.fileModificationDate == rhs.fileModificationDate
            && lhs.cacheHit == rhs.cacheHit
            && lhs.bytesRead == rhs.bytesRead
            && lhs.decodeCount == rhs.decodeCount
            && lhs.decodeDurationNanos == rhs.decodeDurationNanos
            && lhs.cacheTotalBytes == rhs.cacheTotalBytes
            && lhs.identity == rhs.identity
            && lhs.cgImage === rhs.cgImage
    }
}

nonisolated enum ImageDisplayFileOperationError: Error, Equatable, Sendable {
    case missing
    case notRegular
    case tooLarge
    case unreadable
}

/// File operations are injected so the cache's no-read and preflight guarantees are executable
/// in component tests rather than inferred from source text.
nonisolated protocol ImageDisplayFileOperations: Sendable {
    func snapshot(
        at url: URL,
        locationGeneration: UInt64,
        maximumEncodedBytes: Int64
    ) throws -> FileIdentitySnapshot
    func readData(at url: URL, maximumBytes: Int64) throws -> Data
}

nonisolated struct DefaultImageDisplayFileOperations: ImageDisplayFileOperations {
    func snapshot(
        at url: URL,
        locationGeneration: UInt64,
        maximumEncodedBytes: Int64
    ) throws -> FileIdentitySnapshot {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw ImageDisplayFileOperationError.missing
        }
        let canonical = url.standardizedFileURL
        guard canonical.resolvingSymlinksInPath() == canonical else {
            throw ImageDisplayFileOperationError.notRegular
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: canonical.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let modified = attributes[.modificationDate] as? Date,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value else {
            throw ImageDisplayFileOperationError.notRegular
        }
        guard size <= maximumEncodedBytes else { throw ImageDisplayFileOperationError.tooLarge }
        return FileIdentitySnapshot(
            canonicalURL: canonical,
            fileSize: size,
            modificationTime: modified.timeIntervalSinceReferenceDate,
            device: device,
            inode: inode,
            locationGeneration: locationGeneration
        )
    }

    func readData(at url: URL, maximumBytes: Int64) throws -> Data {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              Int64(data.count) <= maximumBytes else {
            throw ImageDisplayFileOperationError.unreadable
        }
        return data
    }
}

/// Deterministic decoded-image LRU. The service is its sole production owner.
nonisolated struct ImageDisplayCache {
    static let maxBytes = 64 * 1024 * 1024

    private struct Entry: @unchecked Sendable {
        let image: CGImage
        let byteCost: Int
    }

    private var entries: [ImageReferenceKey: Entry] = [:]
    private var order: [ImageReferenceKey] = []
    private(set) var totalBytes = 0

    mutating func image(for key: ImageReferenceKey) -> CGImage? {
        guard let entry = entries[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return entry.image
    }

    mutating func store(_ image: CGImage, cost: Int, for key: ImageReferenceKey) {
        if let old = entries.removeValue(forKey: key) {
            totalBytes -= old.byteCost
            order.removeAll { $0 == key }
        }
        entries[key] = Entry(image: image, byteCost: max(cost, 1))
        order.append(key)
        totalBytes += max(cost, 1)
        while totalBytes > Self.maxBytes, let oldest = order.first {
            order.removeFirst()
            if let removed = entries.removeValue(forKey: oldest) {
                totalBytes -= removed.byteCost
            }
        }
    }

    mutating func clear() {
        entries.removeAll()
        order.removeAll()
        totalBytes = 0
    }
}

/// One service owns metadata identity, off-main decode, in-flight coalescing, and decoded cache.
/// The actor boundary prevents a view or parse coordinator from growing a second image route.
actor ImageDisplayService {
    static let maximumEncodedBytes: Int64 = 256 * 1024 * 1024
    static let maximumPixelDimension = 8_192
    static let supportedUTIs: Set<String> = [
        UTType.png.identifier, UTType.jpeg.identifier, UTType.gif.identifier,
        UTType.heic.identifier, UTType.heif.identifier,
        "public.png", "public.jpeg", "public.gif", "public.heic", "public.heif"
    ]

    private struct DecodedCore: @unchecked Sendable {
        let image: CGImage
        let contentType: String
        let sourcePixelWidth: Int
        let sourcePixelHeight: Int
        let byteCost: Int
        let modificationDate: Date?
        let bytesRead: Int
        let decodeDurationNanos: UInt64
    }

    private let fileOperations: any ImageDisplayFileOperations
    private let imageIO: ImageIOExecutor
    private var cache = ImageDisplayCache()
    private var inFlight: [ImageReferenceKey: Task<Result<DecodedCore, LocalImageResolveFailure>, Never>] = [:]

    init(
        fileOperations: any ImageDisplayFileOperations = DefaultImageDisplayFileOperations(),
        imageIO: ImageIOExecutor = .shared
    ) {
        self.fileOperations = fileOperations
        self.imageIO = imageIO
    }

    func clear() {
        cache.clear()
        inFlight.removeAll()
    }

    func cachedByteCount() -> Int { cache.totalBytes }

    func resolve(_ request: ImageDecodeRequest) async -> Result<ImageDisplayDescriptor, LocalImageResolveFailure> {
        guard !Task.isCancelled else { return .failure(.staleVersion) }
        if let scheme = URL(string: request.destination)?.scheme?.lowercased(),
           ["http", "https", "ftp"].contains(scheme) {
            return .failure(.remoteURL)
        }
        if request.destination.hasPrefix("//") {
            return .failure(.remoteURL)
        }
        guard let resolvedURL = Self.containedURL(destination: request.destination, documentURL: request.documentURL) else {
            return .failure(.missingFile)
        }
        let snapshot: FileIdentitySnapshot
        do {
            snapshot = try await imageIO.run {
                try self.fileOperations.snapshot(
                    at: resolvedURL,
                    locationGeneration: request.locationGeneration,
                    maximumEncodedBytes: Self.maximumEncodedBytes
                )
            }
        } catch let error as ImageDisplayFileOperationError {
            return .failure(Self.map(error))
        } catch {
            return .failure(.missingFile)
        }
        let key = ImageReferenceKey(snapshot: snapshot, request: request)
        if let image = cache.image(for: key) {
            return .success(Self.descriptor(from: image, core: nil, snapshot: snapshot, key: key, request: request, cacheHit: true, cacheTotalBytes: cache.totalBytes))
        }
        if let task = inFlight[key] {
            return await coalescedResult(await task.value, snapshot: snapshot, key: key, request: request)
        }
        let fileOperations = self.fileOperations
        let imageIO = self.imageIO
        let task = Task<Result<DecodedCore, LocalImageResolveFailure>, Never> {
            await imageIO.run {
                Self.decode(
                    snapshot: snapshot,
                    request: request,
                    fileOperations: fileOperations
                )
            }
        }
        inFlight[key] = task
        let decoded = await task.value
        inFlight[key] = nil
        guard !Task.isCancelled else { return .failure(.staleVersion) }
        switch decoded {
        case .failure(let error):
            return .failure(error)
        case .success(let core):
            if let intent = request.intent {
                intent.recorder.add(intent) {
                    $0.imageDecodes += 1
                    $0.fileBytesRead += core.bytesRead
                }
            }
            cache.store(core.image, cost: core.byteCost, for: key)
            return .success(Self.descriptor(from: core.image, core: core, snapshot: snapshot, key: key, request: request, cacheHit: false, cacheTotalBytes: cache.totalBytes))
        }
    }

    private func coalescedResult(
        _ result: Result<DecodedCore, LocalImageResolveFailure>,
        snapshot: FileIdentitySnapshot,
        key: ImageReferenceKey,
        request: ImageDecodeRequest
    ) async -> Result<ImageDisplayDescriptor, LocalImageResolveFailure> {
        guard !Task.isCancelled else { return .failure(.staleVersion) }
        switch result {
        case .failure(let error): return .failure(error)
        case .success(let core):
            if cache.image(for: key) == nil {
                cache.store(core.image, cost: core.byteCost, for: key)
            }
            return .success(Self.descriptor(from: core.image, core: nil, snapshot: snapshot, key: key, request: request, cacheHit: true, cacheTotalBytes: cache.totalBytes))
        }
    }

    private static func descriptor(
        from image: CGImage,
        core: DecodedCore?,
        snapshot: FileIdentitySnapshot,
        key: ImageReferenceKey,
        request: ImageDecodeRequest,
        cacheHit: Bool,
        cacheTotalBytes: Int
    ) -> ImageDisplayDescriptor {
        ImageDisplayDescriptor(
            nodeID: request.nodeID,
            sourceRevision: request.sourceRevision,
            locationGeneration: request.locationGeneration,
            requestGeneration: request.requestGeneration,
            resolvedURL: snapshot.canonicalURL,
            contentType: core?.contentType ?? "cached",
            pixelWidth: core?.sourcePixelWidth ?? image.width,
            pixelHeight: core?.sourcePixelHeight ?? image.height,
            displayPixelWidth: image.width,
            displayPixelHeight: image.height,
            byteCost: core?.byteCost ?? max(image.bytesPerRow * image.height, 1),
            fileModificationDate: core?.modificationDate,
            cacheHit: cacheHit,
            bytesRead: core?.bytesRead ?? 0,
            decodeCount: core == nil ? 0 : 1,
            decodeDurationNanos: core?.decodeDurationNanos ?? 0,
            cacheTotalBytes: cacheTotalBytes,
            cgImage: image,
            identity: snapshot
        )
    }

    private static func decode(
        snapshot: FileIdentitySnapshot,
        request: ImageDecodeRequest,
        fileOperations: any ImageDisplayFileOperations
    ) -> Result<DecodedCore, LocalImageResolveFailure> {
        let start = DispatchTime.now().uptimeNanoseconds
        let data: Data
        do {
            data = try fileOperations.readData(at: snapshot.canonicalURL, maximumBytes: maximumEncodedBytes)
        } catch let error as ImageDisplayFileOperationError {
            return .failure(map(error))
        } catch {
            return .failure(.missingFile)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return .failure(.corrupt)
        }
        let uti = CGImageSourceGetType(source).map { $0 as String } ?? ""
        guard supportedUTIs.contains(uti) else { return .failure(.unsupportedType) }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(
            source, 0, [kCGImageSourceShouldCache: false] as CFDictionary
        ) as? [CFString: Any] else { return .failure(.corrupt) }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0 else { return .failure(.corrupt) }
        guard width <= maximumPixelDimension, height <= maximumPixelDimension else {
            return .failure(.oversizeDimensions(width: width, height: height))
        }
        let targetPixels = max(1, Int(ceil(CGFloat(request.pixelTarget) * max(request.backingScale, 1))))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(targetPixels, maximumPixelDimension),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return .failure(.decodeFailed)
        }
        let modificationDate = (try? snapshot.canonicalURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return .success(DecodedCore(
            image: image,
            contentType: uti,
            sourcePixelWidth: width,
            sourcePixelHeight: height,
            byteCost: max(image.bytesPerRow * image.height, 1),
            modificationDate: modificationDate,
            bytesRead: data.count,
            decodeDurationNanos: DispatchTime.now().uptimeNanoseconds &- start
        ))
    }

    private static func containedURL(destination: String, documentURL: URL?) -> URL? {
        guard let documentURL,
              destination.hasPrefix("assets/"),
              destination.count > "assets/".count else { return nil }
        let filename = String(destination.dropFirst("assets/".count))
        guard !filename.isEmpty, !filename.contains("/"), !filename.contains("\\") else { return nil }
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "gif", "heic", "heif"].contains(ext) else { return nil }
        let assets = documentURL.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true).standardizedFileURL
        let candidate = assets.appendingPathComponent(filename).standardizedFileURL
        guard candidate.deletingLastPathComponent() == assets else { return nil }
        return candidate
    }

    private static func map(_ error: ImageDisplayFileOperationError) -> LocalImageResolveFailure {
        switch error {
        case .missing, .unreadable: return .missingFile
        case .notRegular: return .unsupportedType
        case .tooLarge: return .encodedFileTooLarge
        }
    }
}

@MainActor
extension ImageDisplayDescriptor {
    func nsImage(backingScale: CGFloat) -> NSImage {
        NSImage(
            cgImage: cgImage,
            size: NSSize(
                width: CGFloat(displayPixelWidth) / max(backingScale, 1),
                height: CGFloat(displayPixelHeight) / max(backingScale, 1)
            )
        )
    }
}
