//
//  AssetDirectoryStore.swift
//  Markdown Editor
//

import Darwin
import Foundation

// REQ-065–071/077: non-reentrant keyed lease + descriptor-relative exclusive publication.

nonisolated struct StorageLeaseKey: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
    let childName: String
}

nonisolated struct CreatedAssetPin: Sendable {
    let filename: String
    let identity: FileIdentity
    /// Private hard-link path under staging used as identity pin until commit/rollback.
    let pinPath: String?
}

nonisolated struct AssetPublishResult: Sendable {
    let published: [PublishedImage]
    let createdPins: [CreatedAssetPin]
    let createdAssetsDirectory: FileIdentity?
    let assetsPath: String
    let parentIdentity: DocumentParentIdentity
}

/// Process-wide non-reentrant lease registry. Holding the lease across await boundaries is done by
/// keeping the `LeaseHold` alive until the async storage transaction finishes.
nonisolated final class StorageLeaseRegistry: @unchecked Sendable {
    static let shared = StorageLeaseRegistry()

    private let lock = NSLock()
    private var held: Set<StorageLeaseKey> = []
    private var waiters: [StorageLeaseKey: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(_ key: StorageLeaseKey) async -> LeaseHold {
        await withCheckedContinuation { cont in
            lock.lock()
            if !held.contains(key) {
                held.insert(key)
                lock.unlock()
                cont.resume()
            } else {
                waiters[key, default: []].append(cont)
                lock.unlock()
            }
        }
        return LeaseHold(registry: self, key: key)
    }

    fileprivate func release(_ key: StorageLeaseKey) {
        lock.lock()
        held.remove(key)
        let next = waiters[key]?.first
        if var list = waiters[key], !list.isEmpty {
            list.removeFirst()
            if list.isEmpty {
                waiters[key] = nil
            } else {
                waiters[key] = list
            }
            held.insert(key)
            lock.unlock()
            next?.resume()
        } else {
            lock.unlock()
        }
    }
}

nonisolated final class LeaseHold: @unchecked Sendable {
    private let registry: StorageLeaseRegistry
    private let key: StorageLeaseKey
    private var released = false

    init(registry: StorageLeaseRegistry, key: StorageLeaseKey) {
        self.registry = registry
        self.key = key
    }

    deinit { release() }

    func release() {
        guard !released else { return }
        released = true
        registry.release(key)
    }
}

nonisolated enum AssetDirectoryStore {
    static func publish(
        artifacts: [StagedImageArtifact],
        documentURL: URL,
        executor: ImageIOExecutor = .shared,
        leaseRegistry: StorageLeaseRegistry = .shared
    ) async throws -> AssetPublishResult {
        let parentPath = documentURL.deletingLastPathComponent().path
        // Open parent identity on executor before taking lease key.
        let parentIdentity: DocumentParentIdentity = try await executor.run {
            let fd = try POSIXFileOps.openDirectory(parentPath)
            defer { close(fd) }
            let id = try POSIXFileOps.fstatIdentity(fd)
            return DocumentParentIdentity(device: id.device, inode: id.inode)
        }
        let key = StorageLeaseKey(
            device: parentIdentity.device,
            inode: parentIdentity.inode,
            childName: "assets"
        )
        let hold = await leaseRegistry.acquire(key)
        defer { hold.release() }

        return try await executor.run {
            try publishLocked(artifacts: artifacts, parentPath: parentPath, parentIdentity: parentIdentity)
        }
    }

    static func rollback(
        pins: [CreatedAssetPin],
        assetsPath: String,
        createdAssetsDirectory: FileIdentity?,
        executor: ImageIOExecutor = .shared
    ) async {
        await executor.run {
            let assetsFD = open(assetsPath, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard assetsFD >= 0 else { return }
            defer { close(assetsFD) }
            for pin in pins {
                _ = try? POSIXFileOps.unlinkChildIfIdentityMatches(
                    dirFD: assetsFD,
                    name: pin.filename,
                    expected: pin.identity
                )
                if let pinPath = pin.pinPath {
                    unlink(pinPath)
                }
            }
            if let created = createdAssetsDirectory {
                if let current = try? POSIXFileOps.fstatIdentity(assetsFD), current == created {
                    let names = (try? POSIXFileOps.enumerateNames(directoryFD: assetsFD)) ?? []
                    let visible = names.filter { $0 != "." && $0 != ".." && !$0.hasPrefix(".md-editor-") && !$0.hasPrefix(".pin-") }
                    if visible.isEmpty {
                        let parent = (assetsPath as NSString).deletingLastPathComponent
                        let parentFD = open(parent, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
                        if parentFD >= 0 {
                            defer { close(parentFD) }
                            _ = unlinkat(parentFD, "assets", AT_REMOVEDIR)
                        }
                    }
                }
            }
        }
    }

    private static func publishLocked(
        artifacts: [StagedImageArtifact],
        parentPath: String,
        parentIdentity: DocumentParentIdentity
    ) throws -> AssetPublishResult {
        let parentURL = URL(fileURLWithPath: parentPath)
        let assetsURL = parentURL.appendingPathComponent("assets", isDirectory: true)
        var coordinatorError: NSError?
        var publishError: Error?
        var publishResult: AssetPublishResult?
        let coordinator = NSFileCoordinator()
        // ADR-0012: coordinate with file presenters; POSIX exclusive publish remains the boundary.
        coordinator.coordinate(writingItemAt: assetsURL, options: [], error: &coordinatorError) { _ in
            do {
                publishResult = try publishLockedUncoordinated(
                    artifacts: artifacts,
                    parentPath: parentPath,
                    parentIdentity: parentIdentity
                )
            } catch {
                publishError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let publishError { throw publishError }
        guard let publishResult else { throw ImagePlacementError.writeFailed }
        return publishResult
    }

    private static func publishLockedUncoordinated(
        artifacts: [StagedImageArtifact],
        parentPath: String,
        parentIdentity: DocumentParentIdentity
    ) throws -> AssetPublishResult {
        let parentFD = try POSIXFileOps.openDirectory(parentPath)
        defer { close(parentFD) }
        let parentID = try POSIXFileOps.fstatIdentity(parentFD)
        guard parentID.device == parentIdentity.device, parentID.inode == parentIdentity.inode else {
            throw ImagePlacementError.parentChanged
        }

        var createdAssetsIdentity: FileIdentity?
        let assetsFD: Int32
        let existing = openat(
            parentFD, "assets",
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW_ANY | O_RESOLVE_BENEATH
        )
        if existing >= 0 {
            assetsFD = existing
        } else {
            try POSIXFileOps.mkdiratChild(parentFD: parentFD, name: "assets")
            assetsFD = try POSIXFileOps.openChildDirectory(parentFD: parentFD, name: "assets")
            createdAssetsIdentity = try POSIXFileOps.fstatIdentity(assetsFD)
        }
        defer { close(assetsFD) }

        let assetsPath = try POSIXFileOps.path(for: assetsFD)

        let stagingName = ".md-editor-staging-\(UUID().uuidString)"
        try POSIXFileOps.mkdiratChild(parentFD: assetsFD, name: stagingName, mode: 0o700)
        let stagingFD = try POSIXFileOps.openChildDirectory(parentFD: assetsFD, name: stagingName)
        defer {
            close(stagingFD)
            _ = unlinkat(assetsFD, stagingName, AT_REMOVEDIR)
        }

        var published: [PublishedImage] = []
        var pins: [CreatedAssetPin] = []

        func entryMap() throws -> [String: String] {
            let names = try POSIXFileOps.enumerateNames(directoryFD: assetsFD)
            var map: [String: String] = [:]
            for name in names where !name.hasPrefix(".") {
                map[name.lowercased()] = name
            }
            return map
        }

        do {
            for artifact in artifacts {
                var map = try entryMap()
                let stem = ImageAssetPolicy.slug(from: artifact.providerName.map {
                    URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
                })

                let tempName = "tmp-\(UUID().uuidString)"
                let stagingPath = (try POSIXFileOps.path(for: stagingFD) as NSString)
                    .appendingPathComponent(tempName)
                try FileManager.default.copyItem(at: artifact.stagingURL, to: URL(fileURLWithPath: stagingPath))

                let filename = try chooseAndPublish(
                    stem: stem,
                    representation: artifact.representation,
                    sha: artifact.sha256Hex,
                    stagingFD: stagingFD,
                    tempName: tempName,
                    assetsFD: assetsFD,
                    assetsPath: assetsPath,
                    entryMap: &map,
                    pins: &pins
                )

                let dest = URL(fileURLWithPath: assetsPath).appendingPathComponent(filename)
                let created = pins.contains(where: { $0.filename == filename })
                published.append(
                    PublishedImage(
                        filename: filename,
                        markdown: ImageAssetPolicy.markdownReference(filename: filename),
                        destinationURL: dest,
                        wasReused: !created,
                        wasCreatedByThisTransaction: created,
                        identity: pins.first(where: { $0.filename == filename })?.identity
                    )
                )
            }
        } catch {
            // REQ-071: roll back only identity-pinned creations from this batch.
            for pin in pins {
                _ = try? POSIXFileOps.unlinkChildIfIdentityMatches(
                    dirFD: assetsFD,
                    name: pin.filename,
                    expected: pin.identity
                )
                if let pinPath = pin.pinPath { unlink(pinPath) }
            }
            if let created = createdAssetsIdentity,
               let current = try? POSIXFileOps.fstatIdentity(assetsFD),
               current == created {
                let names = (try? POSIXFileOps.enumerateNames(directoryFD: assetsFD)) ?? []
                let visible = names.filter {
                    $0 != "." && $0 != ".." && !$0.hasPrefix(".md-editor-") && !$0.hasPrefix(".pin-")
                }
                if visible.isEmpty {
                    _ = unlinkat(parentFD, "assets", AT_REMOVEDIR)
                }
            }
            throw error
        }

        return AssetPublishResult(
            published: published,
            createdPins: pins,
            createdAssetsDirectory: createdAssetsIdentity,
            assetsPath: assetsPath,
            parentIdentity: parentIdentity
        )
    }

    private static func chooseAndPublish(
        stem: String,
        representation: ImageRepresentation,
        sha: String,
        stagingFD: Int32,
        tempName: String,
        assetsFD: Int32,
        assetsPath: String,
        entryMap: inout [String: String],
        pins: inout [CreatedAssetPin]
    ) throws -> String {
        let ext = representation.canonicalExtension
        var candidates: [String] = ["\(stem).\(ext)"]
        var length = 12
        while length <= sha.count {
            candidates.append("\(stem)-\(String(sha.prefix(length))).\(ext)")
            length += 4
        }
        var n = 0
        while n < 1000 {
            candidates.append("\(stem)-\(sha)-\(n).\(ext)")
            n += 1
        }

        for candidate in candidates {
            let lower = candidate.lowercased()
            if let existingActual = entryMap[lower] {
                // Case-only variant of a different spelling → occupied; try next candidate
                // unless exact portable spelling matches and bytes equal.
                if existingActual != candidate {
                    continue
                }
                // Exact name exists: compare bytes.
                let existingFD = try POSIXFileOps.openChildFileNoFollow(dirFD: assetsFD, name: existingActual)
                defer { close(existingFD) }
                let stagedFD = try POSIXFileOps.openChildFileNoFollow(dirFD: stagingFD, name: tempName)
                defer { close(stagedFD) }
                if try POSIXFileOps.bytesEqual(fdA: existingFD, fdB: stagedFD) {
                    _ = unlinkat(stagingFD, tempName, 0)
                    return existingActual
                }
                continue
            }

            // Name free (case-folded): exclusive publish.
            do {
                try POSIXFileOps.renameExclusive(
                    fromDir: stagingFD,
                    fromName: tempName,
                    toDir: assetsFD,
                    toName: candidate
                )
                let publishedFD = try POSIXFileOps.openChildFileNoFollow(dirFD: assetsFD, name: candidate)
                let identity = try POSIXFileOps.fstatIdentity(publishedFD)
                // Pin via private hard link in staging area sibling.
                let pinName = ".pin-\(UUID().uuidString)"
                let pinPath = (assetsPath as NSString).appendingPathComponent(pinName)
                let linked = linkat(assetsFD, candidate, assetsFD, pinName, 0)
                close(publishedFD)
                if linked != 0 {
                    // Pin optional for commit path; still record identity for rollback.
                    pins.append(CreatedAssetPin(filename: candidate, identity: identity, pinPath: nil))
                } else {
                    pins.append(CreatedAssetPin(filename: candidate, identity: identity, pinPath: pinPath))
                }
                entryMap[lower] = candidate
                return candidate
            } catch is ExclusiveCollision {
                // Winner appeared: compare and maybe reuse.
                guard let actual = try? actualName(assetsFD: assetsFD, lowercased: lower) else {
                    continue
                }
                let existingFD = try POSIXFileOps.openChildFileNoFollow(dirFD: assetsFD, name: actual)
                defer { close(existingFD) }
                let stagedFD = try POSIXFileOps.openChildFileNoFollow(dirFD: stagingFD, name: tempName)
                defer { close(stagedFD) }
                if try POSIXFileOps.bytesEqual(fdA: existingFD, fdB: stagedFD) {
                    _ = unlinkat(stagingFD, tempName, 0)
                    return actual
                }
                continue
            }
        }
        throw ImagePlacementError.writeFailed
    }

    private static func actualName(assetsFD: Int32, lowercased: String) throws -> String? {
        let names = try POSIXFileOps.enumerateNames(directoryFD: assetsFD)
        return names.first { $0.lowercased() == lowercased }
    }
}
