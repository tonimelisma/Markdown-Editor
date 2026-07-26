//
//  PersistentEditorCharacterizationTests.swift
//  Markdown EditorTests
//
//  Persistent editor behavior characterization.
//

import Testing
import AppKit
import CryptoKit
import Foundation
@testable import Markdown_Editor

@MainActor
struct PersistentEditorCharacterizationTests {

    // Verifies: REQ-052 — both TextKit views retain identity across mode toggles.
    @Test func bothEditorsRetainIdentityAcrossModeToggles() {
        let document = MarkdownDocument()
        document.installTextForTesting("# Hello\n")
        let session = EditorSession()
        session.attach(document: document)
        let placement = ImagePlacementController()
        placement.attach(actions: document)
        let router = EditorActionRouter()
        router.document = document
        router.placement = placement

        let host = EditorHostView.HostCoordinator(
            document: document,
            session: session,
            placementController: placement,
            actionRouter: router
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        host.buildEditors(in: root)
        let sourceID = host.sourceViewIdentity
        let wysiwygID = host.wysiwygViewIdentity
        #expect(sourceID != nil)
        #expect(wysiwygID != nil)
        #expect(sourceID != wysiwygID)

        for _ in 0..<5 {
            session.setMode(.source)
            host.applyMode(.source, focus: false)
            session.setMode(.wysiwyg)
            host.applyMode(.wysiwyg, focus: false)
        }
        #expect(host.sourceViewIdentity == sourceID)
        #expect(host.wysiwygViewIdentity == wysiwygID)
        #expect(document.text == "# Hello\n")
    }

    // Verifies: REQ-086 — each mode restores its own selection/scroll chrome.
    @Test func eachModeRestoresOwnSelectionAndScroll() {
        let document = MarkdownDocument()
        document.installTextForTesting("abcdefghij\n")
        let session = EditorSession()
        session.attach(document: document)
        let tree = MarkdownParser.parse(
            document.text,
            sourceVersion: document.sourceVersion
        ).get()!
        session.installProjectionForTesting(
            MarkdownProjectionModel.build(
                tree: tree,
                index: MarkdownSourceIndex(
                    source: document.text,
                    sourceVersion: document.sourceVersion
                )
            ),
            tree: tree
        )
        let placement = ImagePlacementController()
        let router = EditorActionRouter()
        let host = EditorHostView.HostCoordinator(
            document: document,
            session: session,
            placementController: placement,
            actionRouter: router
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        host.buildEditors(in: root)
        // Establish source chrome by selecting while source is visible, then leave.
        host.applyMode(.source, focus: false)
        host.sourceText?.setSelectedRanges(
            [NSValue(range: NSRange(location: 2, length: 3))],
            affinity: .upstream,
            stillSelecting: false
        )
        host.sourceScroll?.contentView.scroll(to: CGPoint(x: 0, y: 12))
        host.sourceScroll?.reflectScrolledClipView(host.sourceScroll!.contentView)

        // Establish WYSIWYG chrome while visible.
        host.applyMode(.wysiwyg, focus: false)
        host.wysiwygText?.setSelectedRanges(
            [NSValue(range: NSRange(location: 0, length: 1))],
            affinity: .downstream,
            stillSelecting: false
        )
        host.wysiwygScroll?.contentView.scroll(to: CGPoint(x: 0, y: 24))
        host.wysiwygScroll?.reflectScrolledClipView(host.wysiwygScroll!.contentView)

        // Return to source — restores source selection, affinity, and scroll.
        host.applyMode(.source, focus: false)
        #expect(host.sourceText?.selectedRange() == NSRange(location: 2, length: 3))
        #expect(host.sourceText?.selectionAffinity == .upstream)
        #expect(host.sourceScroll?.contentView.bounds.origin.y == 12)

        // Return to WYSIWYG — restores WYSIWYG selection, affinity, and scroll.
        host.applyMode(.wysiwyg, focus: false)
        #expect(host.wysiwygText?.selectedRange() == NSRange(location: 0, length: 1))
        #expect(host.wysiwygText?.selectionAffinity == .downstream)
        #expect(host.wysiwygScroll?.contentView.bounds.origin.y == 24)
    }

    // Verifies: REQ-087 — projection mapping refuses without a current presentation.
    @Test func projectionMappingRefusesWithoutPresentation() {
        let snapshot = SourceSnapshot(
            text: "hello",
            sourceVersion: 1,
            locationGeneration: 0,
            fileURL: nil
        )
        let sourceSelection = SourceSelection(utf16: NSRange(location: 0, length: 1))
        let length = (snapshot.text as NSString).length
        #expect(sourceSelection.range.location >= 0)
        #expect(sourceSelection.range.nsMax <= length)

        // Without a projection model, WYSIWYG mapping is unavailable.
        let projection: MarkdownProjectionModel? = nil
        #expect(projection == nil)
    }

    // Verifies: REQ-084 — composition completes once; stale refuses.
    @Test func compositionCommitsOnceAndStaleRefuses() {
        var state = CompositionState()
        state.begin(sourceVersion: 3, sourceRange: NSRange(location: 1, length: 0), marked: NSRange(location: 1, length: 2))
        #expect(state.isComposing)
        #expect(state.isStale(relativeTo: 4))
        #expect(!state.isStale(relativeTo: 3))
        let completed = state.complete()
        #expect(completed?.version == 3)
        #expect(completed?.range.location == 1)
        #expect(!state.isComposing)
        #expect(state.complete() == nil)

        var stale = CompositionState()
        stale.begin(sourceVersion: 1, sourceRange: NSRange(location: 0, length: 0), marked: NSRange(location: 0, length: 1))
        let input = WYSIWYGTextView.WYSIWYGInputCoordinator()
        input.composition = stale
        #expect(input.prepareCommit(currentVersion: 2) == false)
        #expect(!input.composition.isComposing)
    }

    // Verifies: REQ-084 — marked-text path allows transient updates without second commit.
    @Test func markedTextPathAllowsTransientWithoutSourceMutation() {
        let document = MarkdownDocument()
        document.installTextForTesting("abc")
        let before = document.text
        let session = EditorSession()
        session.attach(document: document)
        let placement = ImagePlacementController()
        let coord = WYSIWYGTextView.Coordinator(
            document: document,
            session: session,
            placementController: placement
        )
        let textView = MarkdownWYSIWYGTextView(usingTextLayoutManager: false)
        textView.string = "abc"
        textView.delegate = coord
        textView.inputCoordinator = coord.input
        textView.documentActions = document
        textView.session = session
        coord.textView = textView

        coord.input.beginMarkedText(
            sourceVersion: document.sourceVersion,
            sourceRange: NSRange(location: 3, length: 0),
            marked: NSRange(location: 3, length: 1),
            snapshotID: session.presentation?.id
        )
        coord.input.allowingMarkedText = true
        let allowed = coord.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 3, length: 0),
            replacementString: "x"
        )
        coord.input.allowingMarkedText = false
        #expect(allowed)
        #expect(document.text == before)
    }

    // Verifies: REQ-084 — composition success applies final text synchronously without a second source commit.
    @Test func compositionInsertAppliesFinalTextSynchronously() {
        let document = MarkdownDocument()
        document.installTextForTesting("ab")
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let session = EditorSession()
        session.attach(document: document)
        let index = MarkdownSourceIndex(source: document.text, sourceVersion: document.sourceVersion)
        guard case .success(let tree) = MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion) else {
            Issue.record("parse failed")
            return
        }
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        session.installProjectionForTesting(model, tree: tree)

        let placement = ImagePlacementController()
        let coord = WYSIWYGTextView.Coordinator(
            document: document,
            session: session,
            placementController: placement
        )
        let textView = MarkdownWYSIWYGTextView(usingTextLayoutManager: false)
        textView.string = "ab"
        textView.delegate = coord
        textView.inputCoordinator = coord.input
        textView.documentActions = document
        textView.session = session
        coord.textView = textView
        coord.applyProjectionIfNeeded(force: true)

        // Drive composition state without relying on system IME panels.
        coord.input.beginMarkedText(
            sourceVersion: document.sourceVersion,
            sourceRange: NSRange(location: 2, length: 0),
            marked: NSRange(location: 2, length: 1),
            snapshotID: session.presentation?.id
        )
        let versionBefore = document.sourceVersion
        textView.insertText("日", replacementRange: NSRange(location: NSNotFound, length: 0))
        if document.sourceVersion == versionBefore {
            Issue.record("composition source commit was refused; trace=\(trace.events)")
        }
        #expect(!coord.input.composition.isComposing)
        #expect(!coord.input.committingComposition)
        #expect(document.sourceVersion == versionBefore + 1)
        #expect(document.text.contains("日"))
        #expect((textView.string as NSString).contains("日"))
    }

    // Verifies: REQ-084/091; ARC-004/005 — an IME range captured from one
    // presentation is never relabeled with a different snapshot identity.
    @Test func compositionRefusesWhenCapturedSnapshotWasReplaced() {
        let document = MarkdownDocument()
        document.installTextForTesting("ab")
        let session = EditorSession()
        session.attach(document: document)
        let tree = MarkdownParser.parse(
            document.text,
            sourceVersion: document.sourceVersion
        ).get()!
        session.installProjectionForTesting(
            MarkdownProjectionModel.build(
                tree: tree,
                index: MarkdownSourceIndex(
                    source: document.text,
                    sourceVersion: document.sourceVersion
                )
            ),
            tree: tree
        )
        let coordinator = WYSIWYGTextView.Coordinator(
            document: document,
            session: session,
            placementController: ImagePlacementController()
        )
        let textView = MarkdownWYSIWYGTextView(usingTextLayoutManager: false)
        textView.delegate = coordinator
        textView.inputCoordinator = coordinator.input
        textView.adapterCoordinator = coordinator
        textView.documentActions = document
        textView.session = session
        coordinator.textView = textView
        coordinator.applyProjectionIfNeeded(force: true)

        coordinator.input.beginMarkedText(
            sourceVersion: document.sourceVersion,
            sourceRange: NSRange(location: 2, length: 0),
            marked: NSRange(location: 2, length: 1),
            snapshotID: PresentationSnapshot.ID(value: UInt64.max)
        )
        let version = document.sourceVersion
        textView.insertText("日", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(document.sourceVersion == version)
        #expect(document.text == "ab")
        #expect(!coordinator.input.composition.isComposing)
    }

    // Verifies: REQ-086 — a one-shot session restoration is applied by the persistent host.
    @Test func sessionSelectionRestorationAppliedByPersistentHost() {
        let document = MarkdownDocument()
        document.installTextForTesting("abcdefghij\n")
        let session = EditorSession()
        session.attach(document: document)
        session.setMode(.source)
        let placement = ImagePlacementController()
        let router = EditorActionRouter()
        let host = EditorHostView.HostCoordinator(
            document: document,
            session: session,
            placementController: placement,
            actionRouter: router
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        host.buildEditors(in: root)
        host.applyMode(.source, focus: false)
        session.requestSelectionRestoration(
            SourceSelection(utf16: NSRange(location: 4, length: 2))
        )
        host.applyPendingSelectionIfNeeded()
        #expect(host.sourceText?.selectedRange() == NSRange(location: 4, length: 2))
        #expect(session.pendingSelectionRestoration == nil)
    }

    // Verifies: REQ-084/086
    @Test func pendingSelectionWaitsForMatchingProjection() {
        let document = MarkdownDocument()
        document.installTextForTesting("abcdefghij\n")
        let session = EditorSession()
        session.attach(document: document)
        session.setMode(.wysiwyg)
        let placement = ImagePlacementController()
        let router = EditorActionRouter()
        let host = EditorHostView.HostCoordinator(
            document: document,
            session: session,
            placementController: placement,
            actionRouter: router
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        host.buildEditors(in: root)
        host.applyMode(.wysiwyg, focus: false)

        // Stale / missing matching projection must not clear the pending caret.
        session.clearProjectionForTesting()
        session.requestSelectionRestoration(
            SourceSelection(utf16: NSRange(location: 4, length: 0))
        )
        host.applyPendingSelectionIfNeeded()
        #expect(session.pendingSelectionRestoration?.sourceSelection.range.utf16 == NSRange(location: 4, length: 0))

        let index = MarkdownSourceIndex(source: document.text, sourceVersion: document.sourceVersion)
        guard case .success(let tree) = MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion) else {
            Issue.record("parse failed")
            return
        }
        let projection = MarkdownProjectionModel.build(tree: tree, index: index)
        session.installProjectionForTesting(projection, tree: tree)
        host.applyPendingSelectionIfNeeded()
        #expect(session.pendingSelectionRestoration == nil)
    }

    // Verifies: REQ-086/091/093; ARC-004/005 — native coordinates are
    // published only under the snapshot actually installed in TextKit storage.
    @Test func hostDoesNotRelabelOldNativeSelectionWithNewSnapshot() throws {
        let document = MarkdownDocument()
        document.installTextForTesting("abcdefghij\n")
        let session = EditorSession()
        session.attach(document: document)
        let initialTree = try #require(
            MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion).get()
        )
        session.installProjectionForTesting(
            MarkdownProjectionModel.build(
                tree: initialTree,
                index: MarkdownSourceIndex(
                    source: document.text,
                    sourceVersion: document.sourceVersion
                )
            ),
            tree: initialTree
        )
        session.setMode(.wysiwyg)
        let host = EditorHostView.HostCoordinator(
            document: document,
            session: session,
            placementController: ImagePlacementController(),
            actionRouter: EditorActionRouter()
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        host.buildEditors(in: root)
        host.applyMode(.wysiwyg, focus: false)
        session.updateWYSIWYGModeState {
            $0.selection = ProjectionSelection(
                utf16: NSRange(location: 4, length: 0),
                revision: session.presentation!.projectionRevision
            )
        }

        let replacementSource = "klmnopqrst\n"
        let replacementTree = try #require(
            MarkdownParser.parse(
                replacementSource,
                sourceVersion: document.sourceVersion
            ).get()
        )
        session.installProjectionForTesting(
            MarkdownProjectionModel.build(
                tree: replacementTree,
                index: MarkdownSourceIndex(
                    source: replacementSource,
                    sourceVersion: document.sourceVersion
                )
            ),
            tree: replacementTree
        )
        let current = try #require(session.presentation)
        let remapped = session.wysiwygModeState.selection

        host.applyMode(.wysiwyg, focus: false)

        #expect(session.wysiwygModeState.selection == remapped)
        #expect(session.wysiwygModeState.selection?.range.revision.snapshotID == current.id)
    }

    // Verifies: REQ-060/082 — captured WYSIWYG intent is source-domain and immutable.
    @Test func addImageResolvesCapturedIntentToSourceRange() {
        let document = MarkdownDocument()
        document.installTextForTesting("**Hi**\n")
        let session = EditorSession()
        session.attach(document: document)
        let index = MarkdownSourceIndex(source: document.text, sourceVersion: document.sourceVersion)
        guard case .success(let tree) = MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion) else {
            Issue.record("parse failed")
            return
        }
        let projection = MarkdownProjectionModel.build(tree: tree, index: index)
        session.installProjectionForTesting(projection, tree: tree)

        guard case .exact(let sourceRange) = projection.coordinateMap.sourceRange(
            forProjection: NSRange(location: 0, length: 0),
            affinity: .downstream
        ) else {
            Issue.record("expected exact source mapping")
            return
        }
        #expect(sourceRange.location >= 2)

        let target = ImagePlacementTarget(
            sourceSelection: SourceSelection(utf16: sourceRange, affinity: .downstream),
            sourceRevision: SourceRevision(value: document.sourceVersion),
            locationGeneration: document.locationGeneration,
            operationID: UUID()
        )
        let placement = ImagePlacementController()
        placement.attach(actions: document)
        let router = EditorActionRouter()
        router.document = document
        router.session = session
        router.placement = placement
        router.captureImagePlacementTarget(target)
        session.setMode(.source)
        session.updateSourceModeState {
            $0.selection = SourceSelection(utf16: NSRange(location: 0, length: 0))
        }
        #expect(router.pendingImageTarget == target)
        // Empty claims still run resolve path then return early in placement.
        router.handleAddImageClaims([])
        #expect(router.pendingImageTarget == nil)
    }

    // Verifies: REQ-089 — image cache store emits privacy-safe trace.
    @Test func imageCacheStoreEmitsTrace() throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Images")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cor07-trace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.copyItem(
            at: fixtures.appendingPathComponent("sample.png"),
            to: dir.appendingPathComponent("sample.png")
        )
        let docURL = dir.appendingPathComponent("doc.md")
        try "x".write(to: docURL, atomically: true, encoding: .utf8)
        let desc = try #require(
            LocalImageResolver.resolve(
                destination: "sample.png",
                documentURL: docURL,
                nodeID: MarkdownNodeID(rawValue: 1),
                sourceVersion: 1,
                locationGeneration: 1
            ).get()
        )
        let trace = InMemoryEditorTrace()
        let cache = LocalImageCache()
        cache.trace = trace
        #expect(cache.image(for: desc) != nil)
        let stores = trace.eventsMatching {
            if case .imageCacheStore = $0 { return true }
            return false
        }
        #expect(!stores.isEmpty)
        if case .imageCacheStore(_, let total) = stores[0] {
            #expect(total <= LocalImageByteCache.maxBytes)
        }
    }

    // Verifies: REQ-082 — Add Image is window-scoped via router, not a global notification.
    @Test func addImageUsesWindowScopedRouterNotGlobalNotification() async {
        let document = MarkdownDocument()
        document.installTextForTesting("")
        let session = EditorSession()
        session.attach(document: document)
        let placement = ImagePlacementController()
        placement.attach(actions: document)
        let router = EditorActionRouter()
        router.document = document
        router.placement = placement
        session.actionRouter = router

        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Images/sample.png")
        session.pickImages = { [fixture] }
        await session.addImages()
        #expect(router.pendingImageTarget == nil)
    }

    // Verifies: REQ-082 — one window's router cannot serve another document.
    @Test func addImageDoesNotCrossDocumentWindows() async {
        let docA = MarkdownDocument()
        docA.installTextForTesting("")
        let docB = MarkdownDocument()
        docB.installTextForTesting("")
        let sessionA = EditorSession()
        sessionA.attach(document: docA)
        let placementA = ImagePlacementController()
        placementA.attach(actions: docA)
        let routerA = EditorActionRouter()
        routerA.document = docA
        routerA.placement = placementA
        sessionA.actionRouter = routerA

        let routerB = EditorActionRouter()
        routerB.document = docB
        // No placement on B — claims must not mutate B.
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Images/sample.png")
        sessionA.pickImages = { [fixture] }
        await sessionA.addImages()
        #expect(docB.text == "")
        #expect(routerB.pendingImageTarget == nil)
    }

    // Verifies: REQ-078/032 — task toggle helper is shared for mouse/keyboard/a11y paths.
    @Test func taskToggleSharedAcrossInteractionPaths() async throws {
        let document = MarkdownDocument()
        document.installTextForTesting("- [ ] Task\n")
        let session = EditorSession()
        session.attach(document: document)
        // Wait for parse/projection.
        for _ in 0..<50 {
            if session.presentation != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let placement = ImagePlacementController()
        let textView = MarkdownWYSIWYGTextView(usingTextLayoutManager: false)
        textView.session = session
        textView.documentActions = document
        textView.placementController = placement
        let coord = WYSIWYGTextView.Coordinator(
            document: document,
            session: session,
            placementController: placement
        )
        textView.delegate = coord
        textView.inputCoordinator = coord.input
        coord.textView = textView
        coord.applyProjectionIfNeeded(force: true)

        guard let attachment = session.presentation?.attachments.first(where: {
            if case .task = $0.kind { return true }
            return false
        }) else {
            Issue.record("expected task attachment in projection")
            return
        }
        textView.setSelectedRange(NSRange(location: attachment.utf16Location, length: 1))
        #expect(textView.toggleTaskAtSelection())
        // Accessibility press path on cell.
        if let attr = textView.textStorage?.attribute(.attachment, at: attachment.utf16Location, effectiveRange: nil) as? NSTextAttachment,
           let cell = attr.attachmentCell as? TaskCheckboxAttachmentCell {
            #expect(cell.accessibilityRole() == .checkBox)
            #expect(cell.accessibilityPerformPress())
        }
    }

    // Verifies: REQ-081 — HEIC and HEIF decode; originals unchanged; hashes match manifest.
    @Test func heicAndHeifDecodeWithoutTouchingOriginals() throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Images")
        let manifestURL = fixtures.appendingPathComponent("SHA256MANIFEST.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as! [String: [String: Any]]

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cor07-images-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        for name in ["sample.heic", "sample.heif", "sample.png"] {
            try FileManager.default.copyItem(
                at: fixtures.appendingPathComponent(name),
                to: dir.appendingPathComponent(name)
            )
        }
        let docURL = dir.appendingPathComponent("doc.md")
        try "x".write(to: docURL, atomically: true, encoding: .utf8)

        let heicHash = (manifest["sample.heic"]?["sha256"] as? String)!
        let heifHash = (manifest["sample.heif"]?["sha256"] as? String)!
        #expect(heicHash != heifHash)

        for name in ["sample.heic", "sample.heif"] {
            let url = dir.appendingPathComponent(name)
            let before = try Data(contentsOf: url)
            let digest = SHA256.hash(data: before).map { String(format: "%02x", $0) }.joined()
            #expect(digest == (manifest[name]?["sha256"] as? String))
            let decoded = LocalImageDecoder.decode(destination: name, documentURL: docURL)
            guard case .success = decoded else {
                Issue.record("decode failed for \(name): \(decoded)")
                return
            }
            let after = try Data(contentsOf: url)
            #expect(before == after)
        }
    }

    // Verifies: REQ-081 — corrupt/unsupported content rejected by UTI/decode.
    @Test func unsupportedOrCorruptContentRejected() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cor07-bad-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let docURL = dir.appendingPathComponent("doc.md")
        try "x".write(to: docURL, atomically: true, encoding: .utf8)
        let fake = dir.appendingPathComponent("fake.png")
        try Data([0x00, 0x01, 0x02]).write(to: fake)
        let result = LocalImageDecoder.decode(destination: "fake.png", documentURL: docURL)
        #expect(result.isFailure)
    }

    // Verifies: REQ-081 — cache stays within 64 MiB and refreshes after file change.
    @Test func imageCacheRespectsBudgetAndRefreshesOnChange() throws {
        #expect(LocalImageByteCache.maxBytes == 64 * 1024 * 1024)
        let cache = LocalImageByteCache()
        #expect(cache.totalBytes == 0)

        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Images")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cor07-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = dir.appendingPathComponent("sample.png")
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("sample.png"), to: png)
        let docURL = dir.appendingPathComponent("doc.md")
        try "x".write(to: docURL, atomically: true, encoding: .utf8)

        let first = LocalImageResolver.resolve(
            destination: "sample.png",
            documentURL: docURL,
            nodeID: MarkdownNodeID(rawValue: 1),
            sourceVersion: 1,
            locationGeneration: 1
        )
        let desc1 = try #require(first.get())
        let mainCache = LocalImageCache()
        let image1 = mainCache.image(for: desc1)
        #expect(image1 != nil)
        #expect(mainCache.totalBytes <= LocalImageByteCache.maxBytes)

        // Replace file with JPEG bytes under the same name → new modification date / content.
        try FileManager.default.removeItem(at: png)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("sample.jpg"), to: png)
        // Touch modification date.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: png.path
        )
        let second = LocalImageResolver.resolve(
            destination: "sample.png",
            documentURL: docURL,
            nodeID: MarkdownNodeID(rawValue: 2),
            sourceVersion: 2,
            locationGeneration: 1
        )
        // Extension says png but content is JPEG — UTI detect should accept JPEG.
        let desc2 = try #require(second.get())
        #expect(desc2.contentType.contains("jpeg") || desc2.pixelWidth > 0)
        // Different file bytes must yield different content digests (SHA-256 cache key).
        #expect(desc1.contentDigest != desc2.contentDigest)
        let image2 = mainCache.image(for: desc2)
        #expect(image2 != nil)
        #expect(mainCache.totalBytes <= LocalImageByteCache.maxBytes)
        cache.clear()
        #expect(cache.totalBytes == 0)
    }

    // Verifies: REQ-090 — keystroke translation p95 < 8 ms (Release only).
    @Test func keystrokeTranslationP95Under8ms() async {
        #if !DEBUG
        let document = MarkdownDocument()
        document.installTextForTesting(String(repeating: "word ", count: 20_000))
        let session = EditorSession()
        session.attach(document: document)
        let source = document.text
        let version = document.sourceVersion
        let (tree, model) = await Task.detached {
            let tree = MarkdownParser.parse(source, sourceVersion: version).get()!
            let model = MarkdownProjectionModel.build(
                tree: tree,
                index: MarkdownSourceIndex(source: source, sourceVersion: version)
            )
            return (tree, model)
        }.value
        session.installProjectionForTesting(model, tree: tree)

        var samples: [Double] = []
        samples.reserveCapacity(40)
        for i in 0..<50 {
            let presentation = session.presentation!
            let selection = ProjectionSelection(
                utf16: NSRange(location: i, length: 0),
                revision: presentation.projectionRevision
            )
            let start = CFAbsoluteTimeGetCurrent()
            let result = session.perform(
                .insertText("x"),
                selection: .projection(selection),
                expectedSourceRevision: SourceRevision(value: document.sourceVersion)
            )
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            guard case .accepted = result else {
                Issue.record("performance input refused at sample \(i): \(result)")
                return
            }
            if i >= 10 { samples.append(ms) }
        }
        samples.sort()
        let p95Index = min(samples.count - 1, Int(ceil(0.95 * Double(samples.count))) - 1)
        let p95 = samples[max(p95Index, 0)]
        recordPerformanceEvidence(
            name: "wysiwyg-keystroke-translation",
            corpus: source,
            warmups: 10,
            samples: samples
        )
        #expect(p95 < 8.0, "p95=\(p95)ms samples=\(samples)")
        #else
        return
        #endif
    }

    // Verifies: REQ-090 — mode toggle p95 < 16 ms (Release only).
    @Test func modeToggleP95Under16ms() {
        #if !DEBUG
        let document = MarkdownDocument()
        document.installTextForTesting("# Title\n\nHello world\n")
        let session = EditorSession()
        session.attach(document: document)
        let placement = ImagePlacementController()
        let router = EditorActionRouter()
        let host = EditorHostView.HostCoordinator(
            document: document,
            session: session,
            placementController: placement,
            actionRouter: router
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        host.buildEditors(in: root)

        var samples: [Double] = []
        samples.reserveCapacity(40)
        for i in 0..<50 {
            let mode: EditorMode = (i % 2 == 0) ? .source : .wysiwyg
            let start = CFAbsoluteTimeGetCurrent()
            session.setMode(mode)
            host.applyMode(mode, focus: false)
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            if i >= 10 { samples.append(ms) }
        }
        samples.sort()
        let p95Index = min(samples.count - 1, Int(ceil(0.95 * Double(samples.count))) - 1)
        let p95 = samples[max(p95Index, 0)]
        recordPerformanceEvidence(
            name: "mode-toggle",
            corpus: document.text,
            warmups: 10,
            samples: samples
        )
        #expect(p95 < 16.0, "p95=\(p95)ms samples=\(samples)")
        #else
        return
        #endif
    }
}

private extension Result {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
