//
//  ImageDisplayServiceTests.swift
//  Markdown EditorTests
//

import Foundation
import CoreGraphics
import Testing
@testable import Markdown_Editor

struct ImageDisplayServiceTests {
    @Test func cacheHitStatsButDoesNotReadOrDecode() async throws {
        let fixture = try Fixture()
        let spy = CountingImageFileOperations()
        let service = ImageDisplayService(fileOperations: spy)
        let request = fixture.request(serviceGeneration: 1)

        let first = try #require((await service.resolve(request)).get())
        let readsAfterMiss = spy.reads
        let second = try #require((await service.resolve(request)).get())

        #expect(first.cgImage === second.cgImage)
        #expect(spy.snapshots == 2, "metadata identity is checked on every lookup")
        #expect(readsAfterMiss == 1)
        #expect(spy.reads == 1, "a metadata-valid cache hit must not reopen or read")
        #expect(await service.cachedByteCount() > 0)
    }

    // Verifies: REQ-081 — every supported file representation decodes without rewriting bytes.
    @Test func supportedRepresentationsDecodeWithoutChangingOriginalBytes() async throws {
        let fixture = try Fixture()
        let service = ImageDisplayService()
        for name in ["sample.png", "sample.jpg", "sample.gif", "sample.heic", "sample.heif"] {
            let source = fixture.sourceFixturesURL.appendingPathComponent(name)
            let destination = fixture.assetsURL.appendingPathComponent(name)
            if name != "sample.png" {
                try FileManager.default.copyItem(at: source, to: destination)
            }
            let before = try Data(contentsOf: destination)
            let request = fixture.request(destination: "assets/\(name)", serviceGeneration: UInt64(name.count))
            let result = await service.resolve(request)
            let descriptor = try #require(result.get(), "failed for \(name): \(result)")
            #expect(descriptor.pixelWidth > 0)
            #expect(descriptor.pixelHeight > 0)
            #expect(descriptor.cgImage.width > 0)
            #expect(try Data(contentsOf: destination) == before)
        }
    }

    @Test func metadataChangeIsExactlyOneNewDecode() async throws {
        let fixture = try Fixture()
        let spy = CountingImageFileOperations()
        let service = ImageDisplayService(fileOperations: spy)
        let request = fixture.request(serviceGeneration: 1)

        _ = try #require((await service.resolve(request)).get())
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(30)],
            ofItemAtPath: fixture.imageURL.path
        )
        _ = try #require((await service.resolve(request)).get())

        #expect(spy.reads == 2)
        #expect(spy.snapshots == 2)
    }

    @Test func backingScaleBoundsDecodedPixelsAndSeparatesKeys() async throws {
        let fixture = try Fixture()
        let service = ImageDisplayService(fileOperations: CountingImageFileOperations())
        let target = 5

        let one = try #require((await service.resolve(fixture.request(
            serviceGeneration: 1, pixelTarget: target, backingScale: 1
        ))).get())
        let two = try #require((await service.resolve(fixture.request(
            serviceGeneration: 2, pixelTarget: target, backingScale: 2
        ))).get())
        let three = try #require((await service.resolve(fixture.request(
            serviceGeneration: 3, pixelTarget: target, backingScale: 3
        ))).get())

        #expect(one.displayPixelWidth <= target)
        #expect(two.displayPixelWidth <= target * 2)
        #expect(three.displayPixelWidth <= target * 3)
        #expect(one.displayPixelWidth < two.displayPixelWidth)
        #expect(two.displayPixelWidth < three.displayPixelWidth)
    }

    @Test func outsideAssetsAndSymlinkAreRejectedBeforeRead() async throws {
        let fixture = try Fixture()
        let spy = CountingImageFileOperations()
        let service = ImageDisplayService(fileOperations: spy)

        let outside = ImageDecodeRequest(
            destination: "../outside.png", documentURL: fixture.documentURL,
            nodeID: MarkdownNodeID(rawValue: 1), sourceRevision: 1,
            locationGeneration: 1, requestGeneration: 1, pixelTarget: 20,
            backingScale: 2, appearance: .light
        )
        if case .success = await service.resolve(outside) {
            Issue.record("outside-assets reference was accepted")
        }

        let link = fixture.assetsURL.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.imageURL)
        if case .success = await service.resolve(fixture.request(destination: "assets/link.png", serviceGeneration: 2)) {
            Issue.record("symlink reference was accepted")
        }
        #expect(spy.snapshots == 1, "symlink rejection may inspect metadata but must not read")
        #expect(spy.reads == 0)
    }

    // Verifies: REQ-081/ARC-023 — encoded-size refusal happens before bulk read.
    @Test func oversizedEncodedFileIsRejectedBeforeRead() async throws {
        let fixture = try Fixture()
        let oversized = fixture.assetsURL.appendingPathComponent("large.png")
        FileManager.default.createFile(atPath: oversized.path, contents: nil)
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(ImageDisplayService.maximumEncodedBytes) + 1)
        try handle.close()
        let spy = CountingImageFileOperations()
        let service = ImageDisplayService(fileOperations: spy)

        guard case .failure(.encodedFileTooLarge) = await service.resolve(
            fixture.request(destination: "assets/large.png", serviceGeneration: 1)
        ) else {
            Issue.record("expected encoded-file size refusal")
            return
        }
        #expect(spy.reads == 0)
    }

    // Verifies: REQ-081 — corrupt content is refused without installing a display result.
    @Test func corruptContentIsRejected() async throws {
        let fixture = try Fixture()
        let corrupt = fixture.assetsURL.appendingPathComponent("corrupt.png")
        try Data([0x00, 0x01, 0x02]).write(to: corrupt)
        let result = await ImageDisplayService().resolve(
            fixture.request(destination: "assets/corrupt.png", serviceGeneration: 1)
        )
        guard case .failure(let failure) = result else {
            Issue.record("expected corrupt-content refusal")
            return
        }
        #expect(failure == .corrupt || failure == .unsupportedType)
    }

    // Verifies: REQ-090 — the service-owned decoded cache remains bounded.
    @Test func decodedCacheHasTheApprovedBound() async throws {
        let fixture = try Fixture()
        let service = ImageDisplayService()
        _ = await service.resolve(fixture.request(serviceGeneration: 1))
        #expect(await service.cachedByteCount() <= ImageDisplayCache.maxBytes)
    }

    @Test func identicalConcurrentRequestsDecodeOnce() async throws {
        let fixture = try Fixture()
        let spy = CountingImageFileOperations(delayNanoseconds: 50_000_000)
        let service = ImageDisplayService(fileOperations: spy)
        let request = fixture.request(serviceGeneration: 1)

        async let first = service.resolve(request)
        async let second = service.resolve(request)
        let firstResult = await first
        let secondResult = await second

        let descriptors: [ImageDisplayDescriptor] = [try firstResult.get(), try secondResult.get()]
        #expect(descriptors.filter(\.cacheHit).count == 1)
        #expect(descriptors.filter { !$0.cacheHit && $0.decodeCount == 1 }.count == 1)
        #expect(descriptors.filter { $0.cacheHit && $0.bytesRead == 0 && $0.decodeCount == 0 }.count == 1)
        #expect(spy.reads == 1)
    }

    // Verifies: REQ-085 — cancellation crossing the off-main decode boundary returns a typed
    // stale result and never reports a successful display application.
    @Test func cancelledDecodeReturnsTypedStaleResult() async throws {
        let fixture = try Fixture()
        let service = ImageDisplayService(fileOperations: CountingImageFileOperations(delayNanoseconds: 100_000_000))
        let task = Task { await service.resolve(fixture.request(serviceGeneration: 1)) }
        try await Task.sleep(for: .milliseconds(10))
        task.cancel()
        let result = await task.value
        #expect(result == .failure(.staleVersion))
    }

    private final class Fixture {
        let directory: URL
        let assetsURL: URL
        let documentURL: URL
        let imageURL: URL
        let sourceFixturesURL: URL

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("cor73-service-" + UUID().uuidString, isDirectory: true)
            assetsURL = directory.appendingPathComponent("assets", isDirectory: true)
            documentURL = directory.appendingPathComponent("document.md")
            imageURL = assetsURL.appendingPathComponent("sample.png")
            sourceFixturesURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/Images")
            try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
            let source = sourceFixturesURL.appendingPathComponent("sample.png")
            try FileManager.default.copyItem(at: source, to: imageURL)
            try "![](assets/sample.png)".write(to: documentURL, atomically: true, encoding: .utf8)
        }

        func request(
            destination: String = "assets/sample.png",
            serviceGeneration: UInt64,
            pixelTarget: Int = 64,
            backingScale: CGFloat = 2
        ) -> ImageDecodeRequest {
            ImageDecodeRequest(
                destination: destination, documentURL: documentURL,
                nodeID: MarkdownNodeID(rawValue: 1), sourceRevision: 1,
                locationGeneration: 1, requestGeneration: serviceGeneration,
                pixelTarget: pixelTarget, backingScale: backingScale, appearance: .light
            )
        }

        func tearDown() {
            try? FileManager.default.removeItem(at: directory)
        }

        deinit {
            tearDown()
        }
    }

    private final class CountingImageFileOperations: ImageDisplayFileOperations, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var snapshots = 0
        private(set) var reads = 0
        private let delayNanoseconds: UInt64
        private let base = DefaultImageDisplayFileOperations()

        init(delayNanoseconds: UInt64 = 0) {
            self.delayNanoseconds = delayNanoseconds
        }

        func snapshot(at url: URL, locationGeneration: UInt64, maximumEncodedBytes: Int64) throws -> FileIdentitySnapshot {
            lock.lock(); snapshots += 1; lock.unlock()
            return try base.snapshot(at: url, locationGeneration: locationGeneration, maximumEncodedBytes: maximumEncodedBytes)
        }

        func readData(at url: URL, maximumBytes: Int64) throws -> Data {
            lock.lock(); reads += 1; lock.unlock()
            if delayNanoseconds > 0 { Thread.sleep(forTimeInterval: Double(delayNanoseconds) / 1_000_000_000) }
            return try base.readData(at: url, maximumBytes: maximumBytes)
        }
    }
}
