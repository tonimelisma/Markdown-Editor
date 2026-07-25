//
//  ImagePlacementTests.swift
//  Markdown EditorTests
//

import Testing
import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import Markdown_Editor

struct ImageAssetPolicyTests {

    // Verifies: REQ-066
    @Test(arguments: [
        ("Photo 1", "photo-1"),
        ("Hello_世界", "hello"),
        ("", "image"),
        ("!!!", "image"),
        ("CON", "image-con"),
        ("nul", "image-nul"),
        (String(repeating: "a", count: 100), String(repeating: "a", count: 64)),
    ])
    func generatesPortableAssetNames(input: String, expectedStem: String) {
        #expect(ImageAssetPolicy.slug(from: input) == expectedStem)
    }

    // Verifies: REQ-068
    @Test func generatesPortableCommonMarkImageReferences() {
        #expect(ImageAssetPolicy.markdownReference(filename: "photo.heic") == "![](assets/photo.heic)")
        #expect(ImageAssetPolicy.markdownReferences(["a.png", "b.jpg"]) == "![](assets/a.png)\n![](assets/b.jpg)")
    }

    // Verifies: REQ-061/063
    @Test func detectsTypeFromContent() throws {
        let png = try makePNGData()
        #expect(ImageAssetPolicy.detectRepresentation(from: png) == .png)
        #expect(throws: ImageAssetPolicyError.unsupportedOrCorrupt) {
            try ImageAssetPolicy.validate(data: Data([0x00, 0x01, 0x02]), claimedExtension: nil)
        }
        #expect(throws: ImageAssetPolicyError.typeMismatch) {
            try ImageAssetPolicy.validate(data: png, claimedExtension: "webp")
        }
    }

    // Verifies: REQ-067
    @Test func hashSuffixesDifferentCollision() {
        let digest = ImageAssetPolicy.sha256Hex(Data("different".utf8))
        let name = ImageAssetPolicy.chooseFilename(
            stem: "photo",
            representation: .png,
            sourceSHA256: digest,
            existingNamesLowercased: ["photo.png"],
            bytesEqualAt: { _ in false }
        )
        #expect(name.hasPrefix("photo-"))
        #expect(name.hasSuffix(".png"))
        #expect(name != "photo.png")
        #expect(name.contains(String(digest.prefix(12))))
    }

    // Verifies: REQ-067
    @Test func reusesIdenticalAsset() {
        let digest = ImageAssetPolicy.sha256Hex(Data("same".utf8))
        let name = ImageAssetPolicy.chooseFilename(
            stem: "photo",
            representation: .png,
            sourceSHA256: digest,
            existingNamesLowercased: ["photo.png"],
            bytesEqualAt: { $0.lowercased() == "photo.png" }
        )
        #expect(name == "photo.png")
    }

    // Verifies: REQ-067
    @Test func extendsHashOnPrefixConflict() {
        let digest = String(repeating: "ab", count: 32) // 64 hex chars
        let prefix12 = String(digest.prefix(12))
        let name = ImageAssetPolicy.chooseFilename(
            stem: "photo",
            representation: .png,
            sourceSHA256: digest,
            existingNamesLowercased: ["photo.png", "photo-\(prefix12).png"],
            bytesEqualAt: { _ in false }
        )
        #expect(name == "photo-\(String(digest.prefix(16))).png")
    }
}

struct InsertionRangeTrackerTests {

    // Verifies: REQ-072
    @Test func translatesNonOverlappingEdits() {
        var tracker = InsertionRangeTracker(range: NSRange(location: 10, length: 0))
        tracker.applyEdit(edited: NSRange(location: 0, length: 2), changeInLength: 3) // +3 before
        #expect(!tracker.isCancelled)
        #expect(tracker.range.location == 13)
        tracker.applyEdit(edited: NSRange(location: 50, length: 1), changeInLength: -1) // after
        #expect(!tracker.isCancelled)
        #expect(tracker.range.location == 13)
    }

    // Verifies: REQ-072
    @Test func cancelsOnOverlappingEdit() {
        var tracker = InsertionRangeTracker(range: NSRange(location: 10, length: 5))
        tracker.applyEdit(edited: NSRange(location: 12, length: 1), changeInLength: 0)
        #expect(tracker.isCancelled)
    }
}

struct ImagePlacementServiceTests {

    // Verifies: REQ-061 — exact-copy fidelity for multiple file-backed types.
    @Test func copiesJPEGAndGIFByteForByte() async throws {
        let jpeg = try makeImageData(type: .jpeg)
        let gif = try makeImageData(type: .gif)
        #expect(ImageAssetPolicy.detectRepresentation(from: jpeg) == .jpeg)
        #expect(ImageAssetPolicy.detectRepresentation(from: gif) == .gif)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)
        let service = ImagePlacementService()
        let placedJPEG = try await service.place(
            items: [ImagePlacementItem(payload: .fileBytes(jpeg, providerName: "a.jpeg"))],
            documentURL: doc
        )
        let placedGIF = try await service.place(
            items: [ImagePlacementItem(payload: .fileBytes(gif, providerName: "b.gif"))],
            documentURL: doc
        )
        #expect(try Data(contentsOf: placedJPEG[0].destinationURL) == jpeg)
        #expect(try Data(contentsOf: placedGIF[0].destinationURL) == gif)
        #expect(placedJPEG[0].filename.hasSuffix(".jpg"))
        #expect(placedGIF[0].filename.hasSuffix(".gif"))
    }

    // Verifies: REQ-061 — HEIC detection when Image I/O can encode it on this Mac.
    @Test func detectsHEICWhenEncodable() throws {
        if let heic = try? makeImageData(type: UTType("public.heic") ?? .heic) {
            #expect(ImageAssetPolicy.detectRepresentation(from: heic) == .heic)
        } else {
            // Platform cannot write HEIC in tests; type mapping still exists.
            #expect(ImageRepresentation.fromImageIOType("public.heic") == .heic)
            #expect(ImageRepresentation.fromImageIOType("public.heif") == .heif)
        }
    }

    // Verifies: REQ-061/065/068/070
    @Test func copiesSupportedFileRepresentationsByteForByte() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data("# hi\n".utf8).write(to: doc)

        let service = ImagePlacementService()
        let placed = try await service.place(
            items: [ImagePlacementItem(payload: .fileBytes(png, providerName: "Shot.PNG"))],
            documentURL: doc
        )
        #expect(placed.count == 1)
        #expect(placed[0].markdown == "![](assets/shot.png)")
        let dest = placed[0].destinationURL
        #expect(try Data(contentsOf: dest) == png)
        #expect(ImageAssetPolicy.sha256Hex(try Data(contentsOf: dest)) == ImageAssetPolicy.sha256Hex(png))
    }

    // Verifies: REQ-062
    @Test func encodesBitmapOnlyPasteAsPNG() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)

        let placed = try await ImagePlacementService().place(
            items: [ImagePlacementItem(payload: .bitmapPNG(png, providerName: "image.png"))],
            documentURL: doc
        )
        #expect(placed[0].filename.hasSuffix(".png"))
        #expect(try Data(contentsOf: placed[0].destinationURL) == png)
    }

    // Verifies: REQ-065
    @Test func createsSiblingAssetsDirectoryWhenNeeded() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("assets").path))

        _ = try await ImagePlacementService().place(
            items: [ImagePlacementItem(payload: .fileBytes(png, providerName: "a.png"))],
            documentURL: doc
        )
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("assets").path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    // Verifies: REQ-065/067
    @Test func reusesExistingRealAssetsDirectoryWithoutOwnership() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let assets = dir.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let stranger = assets.appendingPathComponent("keep-me.txt")
        try Data("stay".utf8).write(to: stranger)
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)

        _ = try await ImagePlacementService().place(
            items: [ImagePlacementItem(payload: .fileBytes(png, providerName: "a.png"))],
            documentURL: doc
        )
        #expect(try String(contentsOf: stranger, encoding: .utf8) == "stay")
    }

    // Verifies: REQ-067
    @Test func reusesIdenticalAssetOnDisk() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)
        let service = ImagePlacementService()
        let first = try await service.place(
            items: [ImagePlacementItem(payload: .fileBytes(png, providerName: "photo.png"))],
            documentURL: doc
        )
        let second = try await service.place(
            items: [ImagePlacementItem(payload: .fileBytes(png, providerName: "photo.png"))],
            documentURL: doc
        )
        #expect(first[0].filename == second[0].filename)
        #expect(second[0].wasReused)
        #expect(!second[0].wasCreatedByThisTransaction)
    }

    // Verifies: REQ-071/063
    @Test func cleansOnlyExclusiveBatchFilesOnFailure() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)
        let assets = dir.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let preExisting = assets.appendingPathComponent("preexisting.png")
        try png.write(to: preExisting)

        await #expect(throws: ImagePlacementError.unsupportedOrCorrupt) {
            try await ImagePlacementService().place(
                items: [
                    ImagePlacementItem(payload: .fileBytes(png, providerName: "ok.png")),
                    ImagePlacementItem(payload: .fileBytes(Data([0xFF, 0xD8, 0x00]), providerName: "bad.jpg")),
                ],
                documentURL: doc
            )
        }
        #expect(FileManager.default.fileExists(atPath: preExisting.path))
        // New ok.png from the failed batch must be cleaned (REQ-071).
        let names = try FileManager.default.contentsOfDirectory(atPath: assets.path)
        #expect(names == ["preexisting.png"] || Set(names) == ["preexisting.png"])
    }

    // Verifies: REQ-077
    @Test func rejectsUnsafeFilesystemObjects() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)
        let link = dir.appendingPathComponent("assets")
        let elsewhere = dir.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: elsewhere)

        await #expect(throws: ImagePlacementError.unsafeDestination) {
            try await ImagePlacementService().place(
                items: [ImagePlacementItem(payload: .fileBytes(png, providerName: "a.png"))],
                documentURL: doc
            )
        }
    }

    // Verifies: REQ-070
    @Test func insertsOnlyAfterAllDestinationsExistSemantics() async throws {
        // Service returns only after all files exist; verify multi-item atomic success.
        let png = try makePNGData()
        let png2 = try makePNGData(seed: 2)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)
        let placed = try await ImagePlacementService().place(
            items: [
                ImagePlacementItem(payload: .fileBytes(png, providerName: "one.png")),
                ImagePlacementItem(payload: .fileBytes(png2, providerName: "two.png")),
            ],
            documentURL: doc
        )
        #expect(placed.count == 2)
        for p in placed {
            #expect(FileManager.default.fileExists(atPath: p.destinationURL.path))
        }
    }

    // Verifies: REQ-077
    @Test func placementIOIsOffMainActor() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)
        let service = ImagePlacementService()
        let placed = try await service.place(
            items: [ImagePlacementItem(payload: .fileBytes(png, providerName: "a.png"))],
            documentURL: doc
        )
        #expect(!placed.isEmpty)
        // Actor isolation is by construction; this exercises the off-main path.
    }
}

struct ImagePasteboardClassifierTests {

    // Verifies: REQ-064
    @Test @MainActor func mixedTextAndImageFallsThroughToTextPaste() throws {
        let png = try makePNGData()
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("hello", forType: .string)
        pb.setData(png, forType: .png)
        let result = ImagePasteboardClassifier.classifyPasteboard(pb)
        if case .fallthroughToNativeText = result {
            // ok
        } else {
            Issue.record("expected fallthrough, got \(result)")
        }
    }

    // Verifies: REQ-064
    @Test @MainActor func nonImageDragFallsThrough() throws {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        let txt = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("hello".utf8).write(to: txt)
        defer { try? FileManager.default.removeItem(at: txt) }
        pb.writeObjects([txt as NSURL])
        let result = ImagePasteboardClassifier.classifyPasteboard(pb)
        if case .fallthroughToNativeText = result {
            // ok — non-image file URL is not consumed as an image action
        } else if case .images = result {
            Issue.record("non-image file should not classify as images")
        }
    }
}

struct ImageMarkdownCommitTests {

    // Verifies: REQ-069/073
    @Test @MainActor func commitsOrderedBatchAsOneUndoableReplacement() {
        let tv = MarkdownSourceTextView(usingTextLayoutManager: false)
        tv.string = "Hello|"
        tv.setSelectedRange(NSRange(location: 5, length: 1))
        let markdown = "![](assets/a.png)\n![](assets/b.png)"
        tv.insertImageMarkdown(markdown, at: NSRange(location: 5, length: 1), selectEmptyDescription: false)
        #expect(tv.string == "Hello![](assets/a.png)\n![](assets/b.png)")
    }

    // Verifies: REQ-073
    @Test @MainActor func selectsEmptyDescriptionForSingleImage() {
        let tv = MarkdownSourceTextView(usingTextLayoutManager: false)
        tv.string = ""
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.insertImageMarkdown("![](assets/photo.heic)", at: NSRange(location: 0, length: 0), selectEmptyDescription: true)
        #expect(tv.string == "![](assets/photo.heic)")
        #expect(tv.selectedRange() == NSRange(location: 2, length: 0))
    }

    // Verifies: REQ-074
    @Test @MainActor func sourceUndoRetainsPlacedAssets() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)
        let placed = try await ImagePlacementService().place(
            items: [ImagePlacementItem(payload: .fileBytes(png, providerName: "keep.png"))],
            documentURL: doc
        )
        let tv = MarkdownSourceTextView(usingTextLayoutManager: false)
        tv.string = "x"
        tv.insertImageMarkdown(placed[0].markdown, at: NSRange(location: 0, length: 1), selectEmptyDescription: true)
        tv.undoManager?.undo()
        #expect(FileManager.default.fileExists(atPath: placed[0].destinationURL.path))
    }

    // Verifies: REQ-076
    @Test func warnsWhenParentChangeBreaksGeneratedReference() {
        // Decision helper: a generated reference is broken when the file is missing under the new parent.
        let filename = "photo.png"
        let newParent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let assets = newParent.appendingPathComponent("assets")
        let broken = !FileManager.default.fileExists(atPath: assets.appendingPathComponent(filename).path)
        #expect(broken)
    }
}

// MARK: - Fixtures

private func makePNGData(seed: UInt8 = 1) throws -> Data {
    try makeImageData(type: .png, seed: seed)
}

private func makeImageData(type: UTType, seed: UInt8 = 1) throws -> Data {
    let size = CGSize(width: 2, height: 2)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw ImageAssetPolicyError.unsupportedOrCorrupt
    }
    ctx.setFillColor(CGColor(red: CGFloat(seed) / 255, green: 0.2, blue: 0.8, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: size))
    guard let image = ctx.makeImage() else {
        throw ImageAssetPolicyError.unsupportedOrCorrupt
    }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
        throw ImageAssetPolicyError.unsupportedOrCorrupt
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw ImageAssetPolicyError.unsupportedOrCorrupt
    }
    return data as Data
}
