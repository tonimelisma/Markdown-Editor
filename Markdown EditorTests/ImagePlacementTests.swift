//
//  ImagePlacementTests.swift
//  Markdown EditorTests
//

import Testing
import Foundation
import AppKit
import Combine
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
}

struct ImagePlacementStateMachineTests {
    // Verifies: REQ-060/069
    @Test func rejectsSimultaneousBegin() {
        let id1 = ImageActionID()
        var state = ImagePlacementState()
        state = ImagePlacementReducer.reduce(state: state, event: .begin(id1), actionID: nil)!
        #expect(state.phase == .accepted)
        let id2 = ImageActionID()
        #expect(ImagePlacementReducer.reduce(state: state, event: .begin(id2), actionID: nil) == nil)
    }

    // Verifies: REQ-060
    @Test func ignoresLateResultFromOldUUID() {
        let id1 = ImageActionID()
        var state = ImagePlacementState()
        state = ImagePlacementReducer.reduce(state: state, event: .begin(id1), actionID: nil)!
        state = ImagePlacementReducer.reduce(state: state, event: .startStaging, actionID: id1)!
        let id2 = ImageActionID()
        #expect(ImagePlacementReducer.reduce(state: state, event: .fail(.writeFailed), actionID: id2) == nil)
        state = ImagePlacementReducer.reduce(state: state, event: .fail(.writeFailed), actionID: id1)!
        #expect(state.phase == .failed)
        #expect(state.activeID == nil)
    }

    // Verifies: REQ-060
    @Test func reachesCommittedTerminal() {
        let id = ImageActionID()
        var state = ImagePlacementState()
        state = ImagePlacementReducer.reduce(state: state, event: .begin(id), actionID: nil)!
        state = ImagePlacementReducer.reduce(state: state, event: .startStaging, actionID: id)!
        state = ImagePlacementReducer.reduce(state: state, event: .startPublishing, actionID: id)!
        state = ImagePlacementReducer.reduce(state: state, event: .startCommitting, actionID: id)!
        state = ImagePlacementReducer.reduce(state: state, event: .succeed, actionID: id)!
        #expect(state.phase == .committed)
    }
}

struct InsertionRangeTrackerTests {

    // Verifies: REQ-072
    @Test(arguments: [
        // (trackLoc, trackLen, editLoc, editLen, delta, expectCancelled, expectLoc)
        (10, 0, 10, 0, 1, true, 10),   // insert at zero caret
        (10, 0, 0, 2, 3, false, 13),   // before
        (10, 0, 50, 1, -1, false, 10), // after
        (10, 5, 10, 0, 1, true, 10),   // insert at start of non-empty
        (10, 5, 12, 0, 1, true, 10),   // insert inside
        (10, 5, 15, 0, 1, false, 10),  // insert at end — no change
        (10, 5, 12, 1, 0, true, 10),   // replace interior
        (10, 5, 0, 2, 1, false, 11),   // before shift
    ])
    func boundaryTable(
        trackLoc: Int, trackLen: Int,
        editLoc: Int, editLen: Int, delta: Int,
        expectCancelled: Bool, expectLoc: Int
    ) {
        var tracker = InsertionRangeTracker(range: NSRange(location: trackLoc, length: trackLen))
        tracker.applyEdit(edited: NSRange(location: editLoc, length: editLen), changeInLength: delta)
        #expect(tracker.isCancelled == expectCancelled)
        if !expectCancelled {
            #expect(tracker.range.location == expectLoc)
        }
    }
}

struct FilePromiseCollectorTests {
    // Verifies: REQ-060/063
    @Test func collectsExactCountAndResumesOnce() async throws {
        let collector = FilePromiseCallbackCollector(expectedCount: 2)
        Task {
            try? await Task.sleep(for: .milliseconds(10))
            collector.note(url: URL(fileURLWithPath: "/tmp/a.png"), error: nil)
            collector.note(url: URL(fileURLWithPath: "/tmp/b.png"), error: nil)
        }
        let urls = try await collector.wait()
        #expect(urls.count == 2)
    }

    // Verifies: REQ-060 — callbacks may finish before wait() registers.
    @Test func returnsStoredResultWhenCompletedBeforeWait() async throws {
        let collector = FilePromiseCallbackCollector(expectedCount: 1)
        collector.note(url: URL(fileURLWithPath: "/tmp/a.png"), error: nil)
        let urls = try await collector.wait()
        #expect(urls.count == 1)
    }

    // Verifies: REQ-063
    @Test func rejectsProviderError() async {
        let collector = FilePromiseCallbackCollector(expectedCount: 1)
        Task {
            collector.note(url: nil, error: ImagePlacementError.promiseFailed)
        }
        await #expect(throws: FilePromiseCollectorError.providerError) {
            _ = try await collector.wait()
        }
    }
}

struct ImageIOExecutorTests {
    // Verifies: REQ-077
    @Test func workRunsOffMainQueue() async {
        let executor = ImageIOExecutor(name: "test.imageio")
        let onMain = await executor.run {
            Thread.isMainThread
        }
        #expect(onMain == false)
        #expect(executor.isOnExecutorQueue == false) // we're back on caller
    }
}

struct AssetDirectoryStoreTests {
    // Verifies: REQ-061/065/068/070
    @Test func copiesSupportedFileRepresentationsByteForByte() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data("# hi\n".utf8).write(to: doc)

        let staging = dir.appendingPathComponent("stage", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let stagedFile = staging.appendingPathComponent("x")
        try png.write(to: stagedFile)
        let artifact = StagedImageArtifact(
            stagingURL: stagedFile,
            providerName: "Shot.PNG",
            representation: .png,
            sha256Hex: ImageAssetPolicy.sha256Hex(png),
            byteCount: png.count
        )
        let result = try await AssetDirectoryStore.publish(artifacts: [artifact], documentURL: doc)
        #expect(result.published.count == 1)
        #expect(result.published[0].markdown == "![](assets/shot.png)")
        #expect(try Data(contentsOf: result.published[0].destinationURL) == png)
    }

    // Verifies: REQ-061 — JPEG/GIF exact copy
    @Test func copiesJPEGAndGIFByteForByte() async throws {
        let jpeg = try makeImageData(type: .jpeg)
        let gif = try makeImageData(type: .gif)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)

        for (data, name, rep) in [
            (jpeg, "a.jpeg", ImageRepresentation.jpeg),
            (gif, "b.gif", ImageRepresentation.gif),
        ] as [(Data, String, ImageRepresentation)] {
            let staging = dir.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let staged = staging.appendingPathComponent("x")
            try data.write(to: staged)
            let artifact = StagedImageArtifact(
                stagingURL: staged,
                providerName: name,
                representation: rep,
                sha256Hex: ImageAssetPolicy.sha256Hex(data),
                byteCount: data.count
            )
            let result = try await AssetDirectoryStore.publish(artifacts: [artifact], documentURL: doc)
            #expect(try Data(contentsOf: result.published[0].destinationURL) == data)
        }
    }

    // Verifies: REQ-067
    @Test func reusesIdenticalAssetOnDisk() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)

        func publishOnce() async throws -> AssetPublishResult {
            let staging = dir.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let staged = staging.appendingPathComponent("x")
            try png.write(to: staged)
            let artifact = StagedImageArtifact(
                stagingURL: staged,
                providerName: "photo.png",
                representation: .png,
                sha256Hex: ImageAssetPolicy.sha256Hex(png),
                byteCount: png.count
            )
            return try await AssetDirectoryStore.publish(artifacts: [artifact], documentURL: doc)
        }
        let first = try await publishOnce()
        let second = try await publishOnce()
        #expect(first.published[0].filename == second.published[0].filename)
        #expect(second.published[0].wasReused)
    }

    // Verifies: REQ-065/077
    @Test func rejectsSymlinkedAssetsDirectory() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)
        let elsewhere = dir.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("assets"),
            withDestinationURL: elsewhere
        )
        let staging = dir.appendingPathComponent("stage", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent("x")
        try png.write(to: staged)
        let artifact = StagedImageArtifact(
            stagingURL: staged,
            providerName: "a.png",
            representation: .png,
            sha256Hex: ImageAssetPolicy.sha256Hex(png),
            byteCount: png.count
        )
        await #expect(throws: ImagePlacementError.unsafeDestination) {
            _ = try await AssetDirectoryStore.publish(artifacts: [artifact], documentURL: doc)
        }
    }

    // Verifies: REQ-071 — later item failure rolls back earlier exclusive creates.
    @Test func rollsBackEarlierPublishesWhenLaterItemFails() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)
        let staging = dir.appendingPathComponent("stage", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let good = staging.appendingPathComponent("good")
        try png.write(to: good)
        let missing = staging.appendingPathComponent("missing-source")
        // Second artifact points at a non-existent staging file → copy fails after first publish.
        let artifacts = [
            StagedImageArtifact(
                stagingURL: good,
                providerName: "ok.png",
                representation: .png,
                sha256Hex: ImageAssetPolicy.sha256Hex(png),
                byteCount: png.count
            ),
            StagedImageArtifact(
                stagingURL: missing,
                providerName: "bad.png",
                representation: .png,
                sha256Hex: "deadbeef",
                byteCount: 1
            ),
        ]
        do {
            _ = try await AssetDirectoryStore.publish(artifacts: artifacts, documentURL: doc)
            Issue.record("expected publish to throw")
        } catch let partial as PartialPublishRollback {
            // REQ-101: the store's own internal rollback (this publish call never reaches
            // ImagePlacementController) must still report what it actually removed.
            #expect(partial.removedFileCount == 1)
        } catch {
            Issue.record("expected PartialPublishRollback, got \(error)")
        }
        let assets = dir.appendingPathComponent("assets")
        if FileManager.default.fileExists(atPath: assets.path) {
            let names = try FileManager.default.contentsOfDirectory(atPath: assets.path)
                .filter { !$0.hasPrefix(".") }
            #expect(names.isEmpty)
        }
    }

    // Verifies: REQ-071
    @Test func rollbackRemovesOnlyPinnedCreatedFiles() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)
        let assets = dir.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let pre = assets.appendingPathComponent("preexisting.png")
        try png.write(to: pre)

        let staging = dir.appendingPathComponent("stage", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent("x")
        try png.write(to: staged)
        let artifact = StagedImageArtifact(
            stagingURL: staged,
            providerName: "ok.png",
            representation: .png,
            sha256Hex: ImageAssetPolicy.sha256Hex(png),
            byteCount: png.count
        )
        let result = try await AssetDirectoryStore.publish(artifacts: [artifact], documentURL: doc)
        let removedCount = await AssetDirectoryStore.rollback(
            pins: result.createdPins,
            assetsPath: result.assetsPath,
            createdAssetsDirectory: nil
        )
        #expect(removedCount == 1)
        #expect(FileManager.default.fileExists(atPath: pre.path))
        #expect(!FileManager.default.fileExists(atPath: result.published[0].destinationURL.path))
    }
}

struct ImageBatchPreflightTests {
    // Verifies: REQ-061/063/077
    @Test func stagesRegularPNGAndRejectsCorrupt() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.png")
        try png.write(to: file)
        let arts = try await ImageBatchPreflight.stage(
            claims: [.fileURL(file, providerName: "a.png", declaredType: .png)]
        )
        #expect(arts.count == 1)
        #expect(arts[0].representation == .png)
        #expect(arts[0].sha256Hex == ImageAssetPolicy.sha256Hex(png))

        let bad = dir.appendingPathComponent("bad.png")
        try Data([0x00, 0x01]).write(to: bad)
        await #expect(throws: ImagePlacementError.unsupportedOrCorrupt) {
            _ = try await ImageBatchPreflight.stage(
                claims: [.fileURL(bad, providerName: "bad.png", declaredType: .png)]
            )
        }
    }

    // Verifies: REQ-077
    @Test func rejectsSymlinkSource() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real.png")
        try png.write(to: real)
        let link = dir.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        await #expect(throws: ImagePlacementError.nonRegularSource) {
            _ = try await ImageBatchPreflight.stage(
                claims: [.fileURL(link, providerName: "link.png", declaredType: .png)]
            )
        }
    }
}

struct CanonicalAssetReferenceTests {
    // Verifies: REQ-076
    @Test func findsCanonicalReferencesAndExcludesCode() {
        let source = """
        See ![](assets/photo.png)
        `![](assets/code.png)`
        ```
        ![](assets/fence.png)
        ```
        \\![](assets/escaped.png)
            ![](assets/indent.png)
        """
        let refs = CanonicalAssetReferences.parse(source: source, sourceVersion: 1).values
        #expect(refs.map(\.filename) == ["photo.png"])
    }

    // Verifies: REQ-076
    @Test func detectsBrokenAfterParentChangeIncludingManual() throws {
        let dirOld = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dirNew = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dirOld.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirNew, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: dirOld)
            try? FileManager.default.removeItem(at: dirNew)
        }
        let png = try makePNGData()
        try png.write(to: dirOld.appendingPathComponent("assets/photo.png"))
        let source = "![](assets/photo.png)"
        #expect(
            CanonicalAssetReferences.parse(source: source, sourceVersion: 1)
                .hasBrokenReferences(oldParent: dirOld, newParent: dirNew)
        )
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
}

struct ImageMarkdownCommitTests {
    // Verifies: REQ-069/073
    @Test @MainActor func commitsOrderedBatchAsOneUndoableReplacement() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("Hello|")
        let tv = MarkdownSourceTextView(usingTextLayoutManager: false)
        tv.documentActions = doc
        tv.string = doc.text
        tv.setSelectedRange(NSRange(location: 5, length: 1))
        let markdown = "![](assets/a.png)\n![](assets/b.png)"
        tv.insertImageMarkdown(markdown, at: NSRange(location: 5, length: 1), selectEmptyDescription: false)
        #expect(doc.text == "Hello![](assets/a.png)\n![](assets/b.png)")
        #expect(doc.sourceVersion == 1)
    }

    // Verifies: REQ-073
    @Test @MainActor func selectsEmptyDescriptionForSingleImage() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("")
        var restorations: [SourceSelection] = []
        let cancellable = doc.selectionRestorations.sink { restorations.append($0) }
        defer { cancellable.cancel() }
        let tv = MarkdownSourceTextView(usingTextLayoutManager: false)
        tv.documentActions = doc
        tv.string = ""
        tv.insertImageMarkdown("![](assets/photo.heic)", at: NSRange(location: 0, length: 0), selectEmptyDescription: true)
        #expect(doc.text == "![](assets/photo.heic)")
        #expect(restorations.last?.range.utf16 == NSRange(location: 2, length: 0))
    }

    // Verifies: REQ-074
    @Test @MainActor func sourceUndoRetainsPlacedAssets() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let docURL = dir.appendingPathComponent("note.md")
        try Data().write(to: docURL)
        let staging = dir.appendingPathComponent("stage", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent("x")
        try png.write(to: staged)
        let artifact = StagedImageArtifact(
            stagingURL: staged,
            providerName: "keep.png",
            representation: .png,
            sha256Hex: ImageAssetPolicy.sha256Hex(png),
            byteCount: png.count
        )
        let placed = try await AssetDirectoryStore.publish(artifacts: [artifact], documentURL: docURL)
        let doc = MarkdownDocument()
        doc.installTextForTesting("x")
        let tv = MarkdownSourceTextView(usingTextLayoutManager: false)
        tv.documentActions = doc
        tv.string = "x"
        tv.insertImageMarkdown(placed.published[0].markdown, at: NSRange(location: 0, length: 1), selectEmptyDescription: true)
        doc.undoManager?.undo()
        #expect(FileManager.default.fileExists(atPath: placed.published[0].destinationURL.path))
        #expect(doc.text == "x")
    }
}

struct ImagePlacementControllerLifecycleTests {
    // Verifies: REQ-075
    @Test @MainActor func untitledCancelLeavesIdle() {
        let controller = ImagePlacementController()
        controller.prepareUntitledPlacementForTesting(claims: [
            .bitmapData(Data([0x89]), providerName: "x.png", declaredType: .png)
        ])
        #expect(controller.phaseForTesting == .awaitingSave)
    }

    // Verifies: REQ-101 — Codex PR #24 finding: an action rejected before acceptance (the
    // controller is already busy with a different placement) must still record the attempted
    // claim count and a typed .busy failure, not just present an alert, and must leave the
    // already-active placement's phase untouched.
    @Test @MainActor func busyRejectionIsRecordedWithoutDisturbingActivePlacement() {
        let document = MarkdownDocument()
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let controller = ImagePlacementController()
        controller.attach(actions: document)
        controller.trace = trace
        controller.prepareUntitledPlacementForTesting(claims: [
            .bitmapData(Data([0x89]), providerName: "first.png", declaredType: .png)
        ])
        trace.reset()

        controller.handleImageAction(
            intent: ImagePlacementIntent(
                target: targetForCurrentState(document),
                claims: [
                    .bitmapData(Data([0x89]), providerName: "second-a.png", declaredType: .png),
                    .bitmapData(Data([0x89]), providerName: "second-b.png", declaredType: .png),
                ]
            ),
            documentURL: nil
        )

        #expect(controller.phaseForTesting == .awaitingSave)
        #expect(controller.alert != nil)
        let started = trace.eventsMatching {
            if case .imagePlacementStarted = $0 { return true }
            return false
        }
        #expect(started == [.imagePlacementStarted(claimCount: 2)])
        let failed = trace.eventsMatching {
            if case .imagePlacementFailed = $0 { return true }
            return false
        }
        #expect(failed == [.imagePlacementFailed(reason: .busy, phase: .awaitingSave)])
    }

    // Verifies: REQ-101 — Codex PR #24 finding: an unsuccessful operation-scoped Save is a
    // failure, not a cancellation. The placement log therefore records the .saveFailed reason
    // before its terminal reset, and the user receives the failure-specific route.
    @Test @MainActor func untitledSaveFailureIsRecordedAsPlacementFailure() async {
        final class FailedSave: DocumentSaving {
            func saveDocument() async -> DocumentSaveOutcome { .failed }
        }

        let document = MarkdownDocument()
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let controller = ImagePlacementController()
        controller.attach(actions: document)
        controller.trace = trace
        controller.saveBridgeOverride = FailedSave()

        controller.handleImageAction(
            intent: ImagePlacementIntent(
                target: targetForCurrentState(document),
                claims: [.bitmapData(Data([0x89]), providerName: "x.png", declaredType: .png)]
            ),
            documentURL: nil
        )
        await waitUntilIdle(controller)

        #expect(trace.eventsMatching {
            if case .imagePlacementFailed = $0 { return true }
            return false
        } == [.imagePlacementFailed(reason: .saveFailed, phase: .awaitingSave)])
        #expect(controller.alert == .error(ImagePlacementError.saveFailed.userMessage))
    }

    // Verifies: REQ-019/075 — first URL after untitled Save must not bump document location generation.
    @Test @MainActor func untitledSaveURLDoesNotBumpGenerationForActiveTransaction() async {
        let doc = MarkdownDocument()
        let controller = ImagePlacementController()
        controller.attach(actions: doc)
        controller.prepareUntitledPlacementForTesting(claims: [
            .bitmapData(Data([0x89]), providerName: "x.png", declaredType: .png)
        ])
        let genBefore = doc.locationGeneration
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("note.md")
        try? Data().write(to: url)

        final class AssigningSave: DocumentSaving {
            let doc: MarkdownDocument
            let url: URL
            init(doc: MarkdownDocument, url: URL) {
                self.doc = doc
                self.url = url
            }
            func saveDocument() async -> DocumentSaveOutcome {
                doc.fileURL = url
                return .succeeded
            }
        }
        doc.saveExecutorOverride = AssigningSave(doc: doc, url: url)
        #expect(await doc.saveDocument() == .succeeded)
        controller.updateDocumentURL(doc.fileURL)
        #expect(doc.locationGeneration == genBefore)
        #expect(controller.documentLocationGenerationForTesting == genBefore)
    }

    @MainActor
    private func waitUntilIdle(_ controller: ImagePlacementController, timeoutSeconds: Double = 3) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while controller.phaseForTesting != .idle, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    private func targetForCurrentState(_ document: MarkdownDocument) -> ImagePlacementTarget {
        ImagePlacementTarget(
            sourceSelection: SourceSelection(utf16: NSRange(location: (document.text as NSString).length, length: 0)),
            sourceRevision: SourceRevision(value: document.sourceVersion),
            locationGeneration: document.locationGeneration,
            operationID: UUID()
        )
    }

    // Verifies: REQ-101/102 — a real placement failure (driven through the full
    // handleImageAction pipeline with a genuinely corrupt file, the same seam
    // ImageBatchPreflightTests uses) records the typed reason and the phase it failed in.
    @Test @MainActor func imagePlacementFailureIsRecorded() async throws {
        let document = MarkdownDocument()
        let trace = InMemoryEditorTrace()
        document.trace = trace
        document.installTextForTesting("Some text.")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let docURL = dir.appendingPathComponent("doc.md")
        try Data("Some text.".utf8).write(to: docURL)
        document.fileURL = docURL

        let badFile = dir.appendingPathComponent("bad.png")
        try Data([0x00, 0x01]).write(to: badFile)

        let controller = ImagePlacementController()
        controller.attach(actions: document)
        controller.trace = trace
        controller.handleImageAction(
            intent: ImagePlacementIntent(
                target: targetForCurrentState(document),
                claims: [.fileURL(badFile, providerName: "bad.png", declaredType: .png)]
            ),
            documentURL: document.fileURL
        )
        await waitUntilIdle(controller)

        let failed = trace.eventsMatching {
            if case .imagePlacementFailed = $0 { return true }
            return false
        }
        #expect(failed == [.imagePlacementFailed(reason: .unsupportedOrCorrupt, phase: .staging)])
    }

    // Verifies: REQ-101 — Codex PR #24 finding: a terminal reset (`resetToIdle()`) must itself go
    // through the instrumented transition route, not a raw `state = ImagePlacementState()`, so
    // the run log always shows the phase actually returning to idle, not just the failure that
    // preceded it. Reuses imagePlacementFailureIsRecorded's real corrupt-file pipeline.
    @Test @MainActor func failureRecordsTerminalTransitionBackToIdle() async throws {
        let document = MarkdownDocument()
        let trace = InMemoryEditorTrace()
        document.trace = trace
        document.installTextForTesting("Some text.")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let docURL = dir.appendingPathComponent("doc.md")
        try Data("Some text.".utf8).write(to: docURL)
        document.fileURL = docURL

        let badFile = dir.appendingPathComponent("bad.png")
        try Data([0x00, 0x01]).write(to: badFile)

        let controller = ImagePlacementController()
        controller.attach(actions: document)
        controller.trace = trace
        controller.handleImageAction(
            intent: ImagePlacementIntent(
                target: targetForCurrentState(document),
                claims: [.fileURL(badFile, providerName: "bad.png", declaredType: .png)]
            ),
            documentURL: document.fileURL
        )
        await waitUntilIdle(controller)

        let phaseTransitions: [(ImagePlacementPhase, ImagePlacementPhase)] = trace.events.compactMap {
            if case let .imagePlacementPhase(from, to) = $0 { return (from, to) }
            return nil
        }
        guard let last = phaseTransitions.last else {
            Issue.record("expected at least one recorded phase transition")
            return
        }
        #expect(last.0 == .failed)
        #expect(last.1 == .idle)

        let failedIndex = trace.events.firstIndex {
            if case .imagePlacementFailed = $0 { return true }
            return false
        }
        let idleTransitionIndex = trace.events.firstIndex {
            if case .imagePlacementPhase(_, .idle) = $0 { return true }
            return false
        }
        let failedIdx = try #require(failedIndex)
        let idleIdx = try #require(idleTransitionIndex)
        #expect(failedIdx < idleIdx)
    }

    // Verifies: REQ-101; ARC-016 — the highest-value privacy test in this increment: a
    // revealing filename must never reach any emitted trace line across a real, successful
    // end-to-end placement.
    @Test @MainActor func imagePlacementTraceOmitsFilenames() async throws {
        let logDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let log = DiagnosticLog(directory: logDir, hostKind: .unitTest)
        let document = MarkdownDocument()
        document.trace = JSONLinesEditorTrace(log: log)
        document.installTextForTesting("Some text.")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let docURL = dir.appendingPathComponent("doc.md")
        try Data("Some text.".utf8).write(to: docURL)
        document.fileURL = docURL

        let png = try makePNGData()
        let revealingFile = dir.appendingPathComponent("secret-holiday-photo.png")
        try png.write(to: revealingFile)

        let controller = ImagePlacementController()
        controller.attach(actions: document)
        controller.trace = document.trace
        controller.handleImageAction(
            intent: ImagePlacementIntent(
                target: targetForCurrentState(document),
                claims: [.fileURL(revealingFile, providerName: "secret-holiday-photo.png", declaredType: .png)]
            ),
            documentURL: document.fileURL
        )
        await waitUntilIdle(controller)
        #expect(controller.phaseForTesting == .idle)

        await log.drain()
        let text = (try? String(contentsOf: log.fileURL, encoding: .utf8)) ?? ""
        #expect(!text.isEmpty)
        #expect(!text.contains("secret-holiday-photo"))
        #expect(!text.contains("secret"))
    }

    // Verifies: REQ-101 — the filesystem adversarial rollback path records the removed count,
    // using the same real AssetDirectoryStore.publish/rollback fixtures as
    // rollbackRemovesOnlyPinnedCreatedFiles above.
    @Test @MainActor func rollbackIsRecorded() async throws {
        let png = try makePNGData()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = dir.appendingPathComponent("note.md")
        try Data().write(to: doc)
        let staging = dir.appendingPathComponent("stage", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent("x")
        try png.write(to: staged)
        let artifact = StagedImageArtifact(
            stagingURL: staged,
            providerName: "ok.png",
            representation: .png,
            sha256Hex: ImageAssetPolicy.sha256Hex(png),
            byteCount: png.count
        )
        let result = try await AssetDirectoryStore.publish(artifacts: [artifact], documentURL: doc)

        let trace = InMemoryEditorTrace()
        let controller = ImagePlacementController()
        controller.trace = trace
        await controller.rollbackAndRecord(result)

        let removed = trace.eventsMatching {
            if case .imagePlacementRolledBack = $0 { return true }
            return false
        }
        #expect(removed == [.imagePlacementRolledBack(removedFileCount: 1)])
    }

    // Verifies: ARC-017 — the only way to raise a user-visible alert is
    // ImagePlacementController.presentAlert; no other production file may assign `alert` directly.
    @Test func everyAlertSiteRecordsDiagnostic() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Markdown Editor")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        // `private(set)` only stops assignment from OTHER files — inside
        // ImagePlacementController.swift itself a future bare `alert = ...` could still bypass
        // presentAlert/dismissAlert, so that file is scanned for its own two legitimate
        // assignments rather than excluded outright.
        let allowedOwnerLines: Set<String> = ["alert = kind", "alert = nil"]
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            if file.lastPathComponent == "ImagePlacementController.swift" {
                for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
                    let line = rawLine.trimmingCharacters(in: .whitespaces)
                    guard line.contains("alert ="), !line.contains("alert ==") else { continue }
                    #expect(
                        allowedOwnerLines.contains(line),
                        "ImagePlacementController.swift assigns alert directly outside presentAlert/dismissAlert: \(line)"
                    )
                }
            } else {
                // ".alert = ", not a bare "alert = ": the latter also matches unrelated local
                // variables in other files (for example, an unrelated local AppKit alert).
                // The leading dot is what distinguishes property access on some placement
                // controller from an unrelated local declaration.
                #expect(
                    !contents.contains(".alert = "),
                    "\(file.lastPathComponent) assigns alert directly, bypassing presentAlert/dismissAlert"
                )
            }
        }
    }
}

// MARK: - Fixtures

func makePNGData(seed: UInt8 = 1) throws -> Data {
    try makeImageData(type: .png, seed: seed)
}

func makeImageData(type: UTType, seed: UInt8 = 1) throws -> Data {
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
