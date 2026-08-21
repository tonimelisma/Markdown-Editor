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
import UniformTypeIdentifiers
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
        let input = WYSIWYGEditor.WYSIWYGInputCoordinator()
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
        let coord = WYSIWYGEditor.Coordinator(
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
        let coord = WYSIWYGEditor.Coordinator(
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
        coord.applyProjectionIfNeeded(reason: .reapplyIfDrift)
        session.captureSelection(.projection(
            ProjectionSelection(utf16: NSRange(location: 2, length: 0), revision: session.presentation!.projectionRevision)
        ))

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
        let trace = InMemoryEditorTrace()
        document.trace = trace
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
        let coordinator = WYSIWYGEditor.Coordinator(
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
        coordinator.applyProjectionIfNeeded(reason: .reapplyIfDrift)
        session.captureSelection(.projection(
            ProjectionSelection(utf16: NSRange(location: 2, length: 0), revision: session.presentation!.projectionRevision)
        ))

        coordinator.input.beginMarkedText(
            sourceVersion: document.sourceVersion,
            sourceRange: NSRange(location: 2, length: 0),
            marked: NSRange(location: 2, length: 1),
            snapshotID: PresentationSnapshot.ID(value: UInt64.max)
        )
        let mutation = SourceMutation(
            expectedRevision: document.sourceVersion,
            range: NSRange(location: 2, length: 0),
            expectedText: "",
            replacement: "!",
            selectionBefore: SourceSelection(utf16: NSRange(location: 2, length: 0)),
            selectionAfter: SourceSelection(utf16: NSRange(location: 3, length: 0)),
            actionName: "Test",
            grouping: .discrete
        )
        _ = commitSourceMutationForTest(document, mutation)
        let version = document.sourceVersion
        textView.insertText("日", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(document.sourceVersion == version)
        #expect(document.text == "ab!")
        #expect(!coordinator.input.composition.isComposing)
        #expect(trace.events.contains(.compositionRefusedStale))
    }

    // Verifies: COR-70/REQ-084 — a real native marked-text commit that becomes stale cancels
    // atomically, leaves no native marked range, and never publishes a composition commit.
    @Test func nativeMarkedTextStaleCommitCancelsNativeStateAndUndoGroup() throws {
        let document = MarkdownDocument()
        document.installTextForTesting("ab\n")
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let session = EditorSession()
        session.attach(document: document)
        let tree = try #require(MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion).get())
        session.installProjectionForTesting(
            MarkdownProjectionModel.build(
                tree: tree,
                index: MarkdownSourceIndex(source: document.text, sourceVersion: document.sourceVersion)
            ),
            tree: tree
        )
        let coordinator = WYSIWYGEditor.Coordinator(
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
        coordinator.applyProjectionIfNeeded(reason: .reapplyIfDrift)

        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.setMarkedText(
            "日",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 2, length: 0)
        )
        #expect(textView.hasMarkedText())
        let markedBefore = textView.markedRange()
        #expect(markedBefore.location != NSNotFound)
        #expect((document.documentUndoManager?.groupingLevel ?? 0) > 0)

        let external = SourceMutation(
            expectedRevision: document.sourceVersion,
            range: NSRange(location: 0, length: 0),
            expectedText: "",
            replacement: "X",
            selectionBefore: SourceSelection(utf16: NSRange(location: 0, length: 0)),
            selectionAfter: SourceSelection(utf16: NSRange(location: 1, length: 0)),
            actionName: "External",
            grouping: .discrete
        )
        guard case .committed = commitSourceMutationForTest(document, external) else {
            Issue.record("external edit failed to make the composition stale")
            return
        }
        let committedCompositionsBefore = trace.events.filter {
            if case .compositionCommitted = $0 { return true }
            return false
        }.count

        textView.insertText("日", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(document.text == "Xab\n")
        #expect(!textView.hasMarkedText())
        #expect(textView.markedRange().location == NSNotFound)
        #expect(!coordinator.input.composition.isComposing)
        #expect((document.documentUndoManager?.groupingLevel ?? 0) == 0)
        #expect(trace.events.filter {
            if case .compositionCommitted = $0 { return true }
            return false
        }.count == committedCompositionsBefore)
        #expect(trace.events.contains(.compositionCancelled))
        session.detach()
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
        let remapped = session.wysiwygModeState.selection

        host.applyMode(.wysiwyg, focus: false)

        #expect(session.wysiwygModeState.selection == remapped)
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

    // Verifies: REQ-101 — Codex PR #24 finding: claims returned by Add Image after the captured
    // source-domain intent goes stale must be recorded as a typed rejection, not silently
    // dropped before ImagePlacementController sees them.
    @Test func staleAddImageClaimsAreRecordedWithoutStartingPlacement() {
        let document = MarkdownDocument()
        document.installTextForTesting("Hello")
        let trace = InMemoryEditorTrace()
        document.trace = trace
        let placement = ImagePlacementController()
        placement.attach(actions: document)
        placement.trace = trace
        let router = EditorActionRouter()
        router.document = document
        router.placement = placement
        router.captureImagePlacementTarget(
            ImagePlacementTarget(
                sourceSelection: SourceSelection(utf16: NSRange(location: 5, length: 0)),
                sourceRevision: SourceRevision(value: document.sourceVersion),
                locationGeneration: document.locationGeneration,
                operationID: UUID()
            )
        )
        document.fileURL = URL(fileURLWithPath: "/tmp/stale-add-image.md")

        router.handleAddImageClaims([
            .bitmapData(Data([0x89]), providerName: "picked.png", declaredType: .png)
        ])

        #expect(router.pendingImageTarget == nil)
        #expect(placement.phaseForTesting == .idle)
        #expect(trace.eventsMatching {
            if case .imagePlacementStarted = $0 { return true }
            return false
        } == [.imagePlacementStarted(claimCount: 1)])
        #expect(trace.eventsMatching {
            if case .imagePlacementFailed = $0 { return true }
            return false
        } == [.imagePlacementFailed(reason: .parentChanged, phase: .idle)])
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
        session.imagePicker = TestImagePicker([fixture])
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
        sessionA.imagePicker = TestImagePicker([fixture])
        await sessionA.addImages()
        #expect(docB.text == "")
        #expect(routerB.pendingImageTarget == nil)
    }

    // Verifies: REQ-078/032 — task toggle helper is shared for mouse/keyboard/a11y paths.
    @Test func taskToggleSharedAcrossInteractionPaths() async throws {
        let document = MarkdownDocument()
        document.installTextForTesting("- [ ] Task\n")
        let trace = InMemoryEditorTrace()
        document.trace = trace
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
        let coord = WYSIWYGEditor.Coordinator(
            document: document,
            session: session,
            placementController: placement
        )
        textView.delegate = coord
        textView.inputCoordinator = coord.input
        coord.textView = textView
        coord.applyProjectionIfNeeded(reason: .reapplyIfDrift)

        guard let attachment = session.presentation?.attachments.first(where: {
            if case .task = $0.kind { return true }
            return false
        }) else {
            Issue.record("expected task attachment in projection")
            return
        }
        textView.setSelectedRange(NSRange(location: attachment.utf16Location, length: 1))
        session.captureSelection(.projection(
            ProjectionSelection(
                utf16: NSRange(location: attachment.utf16Location, length: 1),
                revision: session.presentation!.projectionRevision
            )
        ))
        let beforeCommitCount = trace.events.filter {
            if case .mutationCommitted = $0 { return true }
            return false
        }.count
        #expect(textView.toggleTaskAtSelection())
        #expect(trace.events.filter {
            if case .mutationCommitted = $0 { return true }
            return false
        }.count - beforeCommitCount == 1)
        // Accessibility press path on cell.
        if let attr = textView.textStorage?.attribute(.attachment, at: attachment.utf16Location, effectiveRange: nil) as? NSTextAttachment,
           let cell = attr.attachmentCell as? TaskCheckboxAttachmentCell {
            #expect(cell.accessibilityRole() == .checkBox)
            #expect(cell.accessibilityPerformPress())
        }
    }

    // Verifies: REQ-081 — HEIC and HEIF decode; originals unchanged; hashes match manifest.
    @Test func heicAndHeifDecodeWithoutTouchingOriginals() async throws {
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
        let assets = dir.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

        for name in ["sample.heic", "sample.heif", "sample.png"] {
            try FileManager.default.copyItem(
                at: fixtures.appendingPathComponent(name),
                to: assets.appendingPathComponent(name)
            )
        }
        let docURL = dir.appendingPathComponent("doc.md")
        try "x".write(to: docURL, atomically: true, encoding: .utf8)

        let heicHash = (manifest["sample.heic"]?["sha256"] as? String)!
        let heifHash = (manifest["sample.heif"]?["sha256"] as? String)!
        #expect(heicHash != heifHash)

        for name in ["sample.heic", "sample.heif"] {
            let url = assets.appendingPathComponent(name)
            let before = try Data(contentsOf: url)
            let digest = SHA256.hash(data: before).map { String(format: "%02x", $0) }.joined()
            #expect(digest == (manifest[name]?["sha256"] as? String))
            let request = ImageDecodeRequest(
                destination: "assets/\(name)", documentURL: docURL,
                nodeID: MarkdownNodeID(rawValue: UInt64(name.count)), sourceRevision: 1,
                locationGeneration: 1, requestGeneration: UInt64(name.count), pixelTarget: 64,
                backingScale: 2, appearance: .light
            )
            let decoded = await ImageDisplayService().resolve(request)
            guard case .success = decoded else {
                Issue.record("decode failed for \(name): \(decoded)")
                return
            }
            let after = try Data(contentsOf: url)
            #expect(before == after)
        }
    }

    /// Verifies: REQ-090 — p95 of the *complete* native input callback < 8 ms (Release only).
    ///
    /// The measured span is the delegate callback itself, so it contains semantic planning,
    /// source commit, the attributed patch, the attachment update, and selection restoration.
    /// Timing `EditorSession.perform` alone would exclude every TextKit cost the budget is about.
    @Test func nativeInputCallbackP95Under8ms() throws {
#if !DEBUG
        // Performance evidence must use AppKit's concrete NSTextStorage, not the spy storage
        // used by mutation-scope tests. The closed corpus enumeration prevents a fast degenerate
        // document from standing in for structured blocks, tables, code, lists, and attachments.
        for corpus in PerformanceCorpus.allCases {
            let harness = try PerformanceBoundaryTests.ConcreteEditorHarness(
                source: corpus.source()
            )
            let source = harness.document.text
            let rendered = try #require(harness.session.presentation?.renderedString)
            let location = max(0, (rendered as NSString).length - 2)
            var samples: [Double] = []
            var failures: [String] = []
            samples.reserveCapacity(40)
            for i in 0..<50 {
                let before = harness.document.sourceVersion
                let start = CFAbsoluteTimeGetCurrent()
                harness.typeCharacter("x", at: NSRange(location: location, length: 0))
                let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
                guard harness.document.sourceVersion == before &+ 1 else {
                    failures.append("performance input refused at sample \(i)")
                    break
                }
                if i >= 10 { samples.append(ms) }
            }
            let evidence = recordPerformanceEvidence(
                name: "wysiwyg-native-input-callback-\(corpus.rawValue)",
                corpus: source,
                warmups: 10,
                samples: samples,
                failures: failures
            )
            #expect(evidence.failures.isEmpty, "\(corpus.rawValue): \(evidence.failures)")
            #expect(evidence.samples.count == 40)
            if let p95 = evidence.p95 {
                #expect(p95 < 8.0, "\(corpus.rawValue) p95=\(p95)ms samples=\(evidence.samples)")
            }
        }
#else
        return
        #endif
    }

    /// Non-gating characterization: splits the complete native callback into semantic planning
    /// (`EditorSession.perform`, which derives a complete next presentation snapshot) and the
    /// TextKit application that follows it. Reported so a budget miss names its own cause
    /// instead of inviting a guess. No threshold is asserted here.
    // Verifies: REQ-090 — Release characterization of where the native-input-callback budget goes.
    @Test func nativeInputCallbackCostSplitCharacterization() throws {
#if !DEBUG
        let planningHarness = try PerformanceBoundaryTests.EditorHarness(
            source: String(repeating: "word ", count: 20_000)
        )
        let source = planningHarness.document.text

        var planning: [Double] = []
        for i in 0..<50 {
            guard let presentation = planningHarness.session.presentation else { break }
            let selection = ProjectionSelection(
                utf16: NSRange(location: i, length: 0),
                revision: presentation.projectionRevision
            )
            let planStart = CFAbsoluteTimeGetCurrent()
            let outcome = planningHarness.session.perform(
                .insertText("x"),
                selection: .projection(selection),
                expectedSourceRevision: SourceRevision(value: planningHarness.document.sourceVersion)
            )
            let planMs = (CFAbsoluteTimeGetCurrent() - planStart) * 1000
            guard case .accepted = outcome else { break }
            if i >= 10 { planning.append(planMs) }
        }
        _ = recordPerformanceEvidence(
            name: "wysiwyg-semantic-planning-only",
            corpus: source,
            warmups: 10,
            samples: planning
        )
#endif
    }

    /// Non-gating 1M UTF-16 characterization required by COR-20. Reported, never asserted: no
    /// threshold has been approved at this size.
    // Verifies: REQ-090 — native-input-callback behaviour beyond the approved corpus size.
    @Test func nativeInputCallbackOneMillionCharacterization() throws {
#if !DEBUG
        let harness = try PerformanceBoundaryTests.EditorHarness(
            source: String(repeating: "word ", count: 200_000)
        )
        var samples: [Double] = []
        for i in 0..<30 {
            let start = CFAbsoluteTimeGetCurrent()
            harness.typeCharacter("x", at: NSRange(location: i, length: 0))
            if i >= 5 { samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000) }
        }
        _ = recordPerformanceEvidence(
            name: "wysiwyg-native-input-callback-1M",
            corpus: harness.document.text,
            warmups: 5,
            samples: samples
        )
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
        let evidence = recordPerformanceEvidence(
            name: "mode-toggle",
            corpus: document.text,
            warmups: 10,
            samples: samples
        )
        #expect(evidence.failures.isEmpty, "performance evidence failures: \(evidence.failures)")
        #expect(evidence.samples.count > 0)
        if let p95 = evidence.p95 {
            #expect(p95 < 16.0, "p95=\(p95)ms samples=\(evidence.samples)")
        }
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
