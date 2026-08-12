//
//  EncodedImageResourceTests.swift
//  Markdown EditorTests
//

import Foundation
import Testing
@testable import Markdown_Editor

struct EncodedImageResourceTests {
    // Verifies: REQ-081/123
    @Test @MainActor func statIdentityIsStableAndCacheHitNeedsNoDecode() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("encoded-image-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Images/sample.png")
        let imageURL = directory.appendingPathComponent("sample.png")
        try FileManager.default.copyItem(at: source, to: imageURL)
        let documentURL = directory.appendingPathComponent("document.md")
        try "![x](sample.png)".write(to: documentURL, atomically: true, encoding: .utf8)

        let first = try #require(LocalImageResolver.resolve(
            destination: "sample.png", documentURL: documentURL,
            nodeID: MarkdownNodeID(rawValue: 1), sourceVersion: 1, locationGeneration: 1
        ).get())
        let cache = LocalImageCache()
        _ = cache.image(for: first)
        #expect(cache.currentIdentities().contains(first.fileIdentity))
        #expect(cache.image(for: first.fileIdentity) != nil)
        let stable = try #require(LocalImageDecoder.identity(
            destination: "sample.png", documentURL: documentURL, locationGeneration: 1
        ).get())
        #expect(stable == first.fileIdentity)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: imageURL.path
        )
        let changed = try #require(LocalImageDecoder.identity(
            destination: "sample.png", documentURL: documentURL, locationGeneration: 1
        ).get())
        #expect(changed != stable)
    }

    // Verifies: REQ-081 — oversized encoded images are rejected before bulk read/decode.
    @Test func rejectsOversizedEncodedFileBeforeReadAndDecode() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("encoded-image-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("large.png")
        FileManager.default.createFile(atPath: imageURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: imageURL)
        try handle.truncate(atOffset: UInt64(LocalImageDecoder.maxEncodedFileBytes) + 1)
        try handle.close()

        let result = LocalImageDecoder.decode(
            destination: imageURL.lastPathComponent,
            documentURL: directory.appendingPathComponent("document.md")
        )
        // `DecodedImage` carries a `CGImage` and is deliberately not `Equatable`, so the refusal
        // is compared on the error alone. Without the metadata gate this file decodes to
        // `.corrupt`, so the assertion discriminates the size check rather than merely observing
        // that some failure occurred.
        guard case .failure(let failure) = result else {
            Issue.record("expected refusal, got a decoded image")
            return
        }
        #expect(failure == .encodedFileTooLarge)

        let identity = LocalImageDecoder.identity(
            destination: imageURL.lastPathComponent,
            documentURL: directory.appendingPathComponent("document.md"),
            locationGeneration: 0
        )
        guard case .failure(let identityFailure) = identity else {
            Issue.record("metadata identity gate accepted an oversized file")
            return
        }
        #expect(identityFailure == .encodedFileTooLarge)
    }
}
