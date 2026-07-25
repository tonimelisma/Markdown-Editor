//
//  ImagePlacementService.swift
//  Markdown Editor
//

import Foundation
import ImageIO

// REQ-065–071/077: off-main placement — validate, name, exclusive write, containment, cleanup.

nonisolated struct ImagePlacementItem: Sendable {
    enum Payload: Sendable {
        case fileBytes(Data, providerName: String?)
        case bitmapPNG(Data, providerName: String?)
    }

    let payload: Payload
}

nonisolated struct PlacedImage: Sendable, Equatable {
    let filename: String
    let markdown: String
    let destinationURL: URL
    let wasReused: Bool
    let wasCreatedByThisTransaction: Bool
}

nonisolated enum ImagePlacementError: Error, Equatable, Sendable {
    case noDocumentURL
    case unsafeDestination
    case unsupportedOrCorrupt
    case typeMismatch
    case writeFailed
    case partialFailure
}

actor ImagePlacementService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // REQ-070/071/077: place all items; insert no source until every destination exists.
    func place(
        items: [ImagePlacementItem],
        documentURL: URL
    ) async throws -> [PlacedImage] {
        try Task.checkCancellation()
        guard !items.isEmpty else { return [] }

        let parent = documentURL.deletingLastPathComponent()
        let assetsURL = try resolveOrCreateAssetsDirectory(adjacentTo: parent)
        var createdByUs: [URL] = []
        var stagingDir: URL?
        var results: [PlacedImage] = []

        do {
            stagingDir = try makeStagingDirectory()
            for item in items {
                try Task.checkCancellation()
                let placed = try placeOne(item, assetsURL: assetsURL, stagingDir: stagingDir!)
                if placed.wasCreatedByThisTransaction {
                    createdByUs.append(placed.destinationURL)
                }
                results.append(placed)
            }
            // Success — leave created files; clean staging only.
            if let stagingDir {
                try? fileManager.removeItem(at: stagingDir)
            }
            return results
        } catch {
            // REQ-071: remove only staging + exclusive new files from this transaction.
            for url in createdByUs {
                try? fileManager.removeItem(at: url)
            }
            if let stagingDir {
                try? fileManager.removeItem(at: stagingDir)
            }
            throw error
        }
    }

    private func placeOne(
        _ item: ImagePlacementItem,
        assetsURL: URL,
        stagingDir: URL
    ) throws -> PlacedImage {
        let data: Data
        let providerName: String?
        switch item.payload {
        case .fileBytes(let bytes, let name):
            data = bytes
            providerName = name
        case .bitmapPNG(let bytes, let name):
            data = bytes
            providerName = name
        }

        let claimedExt = providerName.flatMap { URL(fileURLWithPath: $0).pathExtension }
        let representation: ImageRepresentation
        do {
            representation = try ImageAssetPolicy.validate(data: data, claimedExtension: claimedExt)
        } catch ImageAssetPolicyError.typeMismatch {
            throw ImagePlacementError.typeMismatch
        } catch {
            throw ImagePlacementError.unsupportedOrCorrupt
        }

        // Bitmap path must already be PNG bytes; file path is exact copy (REQ-061/062).
        if case .bitmapPNG = item.payload, representation != .png {
            throw ImagePlacementError.unsupportedOrCorrupt
        }

        let digest = ImageAssetPolicy.sha256Hex(data)
        let stem = ImageAssetPolicy.slug(from: providerName.map {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
        })

        let existing = try listAssetNames(in: assetsURL)
        let filename = ImageAssetPolicy.chooseFilename(
            stem: stem,
            representation: representation,
            sourceSHA256: digest,
            existingNamesLowercased: Set(existing.map { $0.lowercased() }),
            bytesEqualAt: { name in
                let url = assetsURL.appendingPathComponent(name)
                guard let existingData = try? Data(contentsOf: url) else { return false }
                return existingData == data
            }
        )

        let destination = assetsURL.appendingPathComponent(filename)
        try verifyContainment(destination, within: assetsURL)

        if fileManager.fileExists(atPath: destination.path) {
            // Reuse only when bytes match (already enforced by chooseFilename).
            guard let existingData = try? Data(contentsOf: destination), existingData == data else {
                throw ImagePlacementError.writeFailed
            }
            // Reject if destination is a symlink.
            try rejectSymlinkOrAlias(at: destination)
            return PlacedImage(
                filename: filename,
                markdown: ImageAssetPolicy.markdownReference(filename: filename),
                destinationURL: destination,
                wasReused: true,
                wasCreatedByThisTransaction: false
            )
        }

        // Exclusive create via coordinated write.
        let staged = stagingDir.appendingPathComponent(UUID().uuidString + "." + representation.canonicalExtension)
        try data.write(to: staged, options: .atomic)

        try exclusiveCopy(from: staged, to: destination)
        try verifyContainment(destination, within: assetsURL)
        try rejectSymlinkOrAlias(at: destination)

        // REQ-061: verify final bytes equal source for file-backed copies.
        let written = try Data(contentsOf: destination)
        guard written == data else {
            try? fileManager.removeItem(at: destination)
            throw ImagePlacementError.writeFailed
        }

        return PlacedImage(
            filename: filename,
            markdown: ImageAssetPolicy.markdownReference(filename: filename),
            destinationURL: destination,
            wasReused: false,
            wasCreatedByThisTransaction: true
        )
    }

    // REQ-065/077: sibling assets/ — real directory only; create when needed; no ownership claim.
    private func resolveOrCreateAssetsDirectory(adjacentTo parent: URL) throws -> URL {
        let assets = parent.appendingPathComponent("assets", isDirectory: true)
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: assets.path, isDirectory: &isDir) {
            guard isDir.boolValue else { throw ImagePlacementError.unsafeDestination }
            try rejectSymlinkOrAlias(at: assets)
            try rejectPackage(at: assets)
            let resolved = assets.resolvingSymlinksInPath()
            let resolvedParent = parent.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(resolvedParent.path + "/") || resolved.path == resolvedParent.appendingPathComponent("assets").path else {
                throw ImagePlacementError.unsafeDestination
            }
            return assets
        }
        try fileManager.createDirectory(at: assets, withIntermediateDirectories: false)
        try rejectSymlinkOrAlias(at: assets)
        return assets
    }

    private func listAssetNames(in assetsURL: URL) throws -> [String] {
        guard fileManager.fileExists(atPath: assetsURL.path) else { return [] }
        return try fileManager.contentsOfDirectory(atPath: assetsURL.path)
    }

    private func makeStagingDirectory() throws -> URL {
        let base = fileManager.temporaryDirectory
        let url = base.appendingPathComponent("md-editor-img-" + UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func exclusiveCopy(from source: URL, to destination: URL) throws {
        var coordinatorError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinatorError) { url in
            do {
                // O_EXCL-style: fail if exists.
                if self.fileManager.fileExists(atPath: url.path) {
                    throw ImagePlacementError.writeFailed
                }
                try self.fileManager.copyItem(at: source, to: url)
            } catch {
                copyError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
    }

    private func verifyContainment(_ url: URL, within directory: URL) throws {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let dir = directory.resolvingSymlinksInPath().standardizedFileURL
        let prefix = dir.path.hasSuffix("/") ? dir.path : dir.path + "/"
        guard resolved.path.hasPrefix(prefix), resolved.lastPathComponent == url.lastPathComponent else {
            throw ImagePlacementError.unsafeDestination
        }
    }

    private func rejectSymlinkOrAlias(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isAliasFileKey])
        if values.isSymbolicLink == true || values.isAliasFile == true {
            throw ImagePlacementError.unsafeDestination
        }
    }

    private func rejectPackage(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isPackageKey])
        if values.isPackage == true {
            throw ImagePlacementError.unsafeDestination
        }
    }
}
