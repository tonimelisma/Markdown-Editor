//
//  ImagePlacementCoordinatorTests.swift
//  Markdown EditorTests
//

import Testing
import Foundation
import AppKit
@testable import Markdown_Editor

@MainActor
struct ImagePlacementCoordinatorLifecycleTests {

    // Verifies: REQ-075
    @Test func cancelSaveCreatesNothing() {
        let coordinator = ImagePlacementCoordinator()
        coordinator.noteSaveCancelled()  // no-op when not awaiting
        coordinator.prepareUntitledPlacementForTesting([])
        coordinator.noteSaveCancelled()
        if case .info = coordinator.alert {
            // cancelled
        } else {
            Issue.record("expected cancellation info alert")
        }
    }

    // Verifies: REQ-060/075 — resume path after a document URL appears (post-Save).
    @Test func saveThenResumesPlacement() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)

        let coordinator = ImagePlacementCoordinator()
        let tv = MarkdownSourceTextView(usingTextLayoutManager: false)
        tv.string = "Hello"
        tv.setSelectedRange(NSRange(location: 5, length: 0))
        coordinator.attach(textView: tv)

        coordinator.prepareUntitledPlacementForTesting([
            ImagePlacementItem(payload: .fileBytes(png, providerName: "photo.png"))
        ])
        coordinator.updateDocumentURL(doc)

        let assets = dir.appendingPathComponent("assets")
        for _ in 0..<40 {
            if tv.string.contains("![](assets/"), FileManager.default.fileExists(atPath: assets.path) {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(FileManager.default.fileExists(atPath: assets.path))
        #expect(tv.string.contains("![](assets/"))
    }
}

private func makePNGData(seed: UInt8 = 3) throws -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw ImageAssetPolicyError.unsupportedOrCorrupt
    }
    ctx.setFillColor(CGColor(red: 0.1, green: 0.2, blue: CGFloat(seed) / 255, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    guard let image = ctx.makeImage() else {
        throw ImageAssetPolicyError.unsupportedOrCorrupt
    }
    return try ImageAssetPolicy.encodePNG(from: image)
}
