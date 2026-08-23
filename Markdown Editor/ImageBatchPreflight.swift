//
//  ImageBatchPreflight.swift
//  Markdown Editor
//

import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

// REQ-061–063/077: stage+hash+type-detect all items before any final publish.

nonisolated enum ImageBatchPreflight {
    static func stage(
        claims: [ImageClaim],
        promiseURLs: [URL] = [],
        executor: ImageIOExecutor = .shared
    ) async throws -> [StagedImageArtifact] {
        try await executor.run {
            var artifacts: [StagedImageArtifact] = []
            var promiseIndex = 0
            let stagingRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("md-editor-preflight-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            // Caller / controller cleans stagingRoot via artifact URLs' parent on success/failure.

            for claim in claims {
                switch claim {
                case .fileURL(let url, let providerName, _):
                    let artifact = try stageFile(
                        at: url,
                        providerName: providerName ?? url.lastPathComponent,
                        stagingRoot: stagingRoot
                    )
                    artifacts.append(artifact)

                case .bitmapData(let data, let providerName, _):
                    let png = try encodeBitmapPNG(data)
                    let artifact = try stageBytes(
                        png,
                        providerName: providerName ?? "image.png",
                        stagingRoot: stagingRoot,
                        expected: .png
                    )
                    artifacts.append(artifact)

                case .promiseToken:
                    guard promiseIndex < promiseURLs.count else {
                        throw ImagePlacementError.promiseFailed
                    }
                    let url = promiseURLs[promiseIndex]
                    promiseIndex += 1
                    let artifact = try stageFile(
                        at: url,
                        providerName: url.lastPathComponent,
                        stagingRoot: stagingRoot
                    )
                    artifacts.append(artifact)
                }
            }
            if promiseIndex != promiseURLs.count && claims.contains(where: {
                if case .promiseToken = $0 { return true }
                return false
            }) {
                // Extra promise URLs without tokens are fine if all tokens consumed;
                // mismatch of too few already threw.
            }
            return artifacts
        }
    }

    private static func stageFile(
        at url: URL,
        providerName: String,
        stagingRoot: URL
    ) throws -> StagedImageArtifact {
        let fd = try POSIXFileOps.openRegularFileNoFollow(url.path)
        defer { close(fd) }
        let dest = stagingRoot.appendingPathComponent(UUID().uuidString)
        let (sha, count) = try POSIXFileOps.streamCopyAndHash(fromFD: fd, toPath: dest.path)
        let representation = try detectRepresentation(at: dest)
        let claimedExt = URL(fileURLWithPath: providerName).pathExtension
        try validateClaim(claimedExt: claimedExt, detected: representation)
        return StagedImageArtifact(
            stagingURL: dest,
            providerName: providerName,
            representation: representation,
            sha256Hex: sha,
            byteCount: count
        )
    }

    private static func stageBytes(
        _ data: Data,
        providerName: String,
        stagingRoot: URL,
        expected: ImageRepresentation
    ) throws -> StagedImageArtifact {
        let dest = stagingRoot.appendingPathComponent(UUID().uuidString)
        try POSIXFileOps.writeDataExclusive(toPath: dest.path, data: data)
        let sha = ImageAssetPolicy.sha256Hex(data)
        let representation = try detectRepresentation(at: dest)
        guard representation == expected else { throw ImagePlacementError.unsupportedOrCorrupt }
        return StagedImageArtifact(
            stagingURL: dest,
            providerName: providerName,
            representation: representation,
            sha256Hex: sha,
            byteCount: data.count
        )
    }

    private static func detectRepresentation(at url: URL) throws -> ImageRepresentation {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              let rep = ImageRepresentation.fromImageIOType(type) else {
            throw ImagePlacementError.unsupportedOrCorrupt
        }
        return rep
    }

    private static func validateClaim(claimedExt: String, detected: ImageRepresentation) throws {
        guard !claimedExt.isEmpty else { return }
        let normalized = claimedExt.lowercased()
        let supported = ImageRepresentation.acceptedExtensions
        if !supported.contains(normalized) {
            throw ImagePlacementError.typeMismatch
        }
        // REQ-063: reject when claimed extension disagrees with detected content family.
        //
        // // Compared through `ImageRepresentation.fromExtension` rather than a local switch, so
        // // the extension-to-representation mapping has one owner and `jpg`/`jpeg` are treated as
        // // one representation in exactly one place.
        if ImageRepresentation.fromExtension(normalized) != detected {
            throw ImagePlacementError.typeMismatch
        }
    }

    private static func encodeBitmapPNG(_ data: Data) throws -> Data {
        if ImageAssetPolicy.detectRepresentation(from: data) == .png {
            return data
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImagePlacementError.unsupportedOrCorrupt
        }
        return try ImageAssetPolicy.encodePNG(from: image)
    }
}
