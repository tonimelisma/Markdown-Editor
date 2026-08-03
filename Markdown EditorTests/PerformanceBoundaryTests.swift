//
//  PerformanceBoundaryTests.swift
//  Markdown EditorTests
//
//  COR-20 proof that `.nativeInputCallback` measures the complete native callback — semantic
//  planning, source commit, attributed patch, attachment update, and selection restoration —
//  rather than only the part that was already fast.
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

@MainActor
struct PerformanceBoundaryTests {
    /// Injects a measurable stall inside `NSTextStorage.replaceCharacters`. If the sample were
    /// taken before TextKit application — the defect this test exists to catch — the recorded
    /// duration would not contain the stall.
    // Verifies: REQ-090/103/109; ARC-020
    @Test func nativeInputCallbackSampleEnclosesStorageApplication() throws {
        let stall: TimeInterval = 0.05
        // Two paragraphs, so a bounded patch is visibly smaller than the document.
        let harness = try EditorHarness(source: "Hello world.\n\nSecond paragraph.\n")
        harness.storage.mutationDelay = stall

        harness.typeCharacter("!", at: NSRange(location: 12, length: 0))

        let summary = try #require(
            harness.session.drainPerformanceSummaries().first { $0.metric == .nativeInputCallback }
        )
        #expect(summary.count == 1)
        let recordedSeconds = Double(summary.max) / 1_000_000_000
        #expect(
            recordedSeconds >= stall,
            "callback sample \(recordedSeconds)s excludes the \(stall)s storage stall"
        )
        // The stall was inside a bounded patch, not a document rebuild.
        #expect(harness.storage.fullReplacements == 0)
        #expect(harness.storage.characterReplacements.count == 1)
        let patched = try #require(harness.storage.characterReplacements.first)
        #expect(patched.length < (harness.session.presentation?.renderedString as NSString?)?.length ?? 0)
        #expect(harness.document.text == "Hello world.!\n\nSecond paragraph.\n")
    }

    // Verifies: REQ-103 — ordinary edits feed the sampler and emit no per-keystroke record.
    @Test func ordinaryEditsProduceAggregatesOnlyAndNoPerKeystrokeRecord() throws {
        let trace = InMemoryEditorTrace()
        let harness = try EditorHarness(source: "Hello world.\n", trace: trace)

        for offset in 0..<5 {
            harness.typeCharacter("x", at: NSRange(location: 12 + offset, length: 0))
        }

        let summary = try #require(
            harness.session.drainPerformanceSummaries().first { $0.metric == .nativeInputCallback }
        )
        #expect(summary.count == 5)
        // No performance record per keystroke: aggregates are emitted by the periodic flush only.
        let perKeystroke = trace.eventsMatching {
            if case .performanceSummary = $0 { return true }
            return false
        }
        #expect(perKeystroke.isEmpty)
        #expect(harness.document.text == "Hello world.xxxxx\n")
    }

    // Verifies: REQ-109 — storage drift is resynchronized *and recorded*, never silently.
    @Test func driftedStorageIsResynchronizedAndRecorded() throws {
        let trace = InMemoryEditorTrace()
        let harness = try EditorHarness(source: "Hello world.\n", trace: trace)

        // Diverge applied storage from the snapshot the next keystroke targets.
        harness.storage.replaceCharacters(in: NSRange(location: 0, length: 5), with: "HELLO")
        harness.typeCharacter("!", at: NSRange(location: 12, length: 0))

        let recovered = trace.eventsMatching {
            if case .presentationRecovered = $0 { return true }
            return false
        }
        #expect(recovered.count == 1)
        // The drifted keystroke changed no source.
        #expect(harness.document.text == "Hello world.\n")
        #expect(harness.textView.string == harness.session.presentation?.renderedString)
    }

    // Verifies: REQ-109 — a patch whose surrounding text is not identical in both snapshots is
    // refused outright rather than applied on an assumption.
    @Test func patchRefusesWhenSurroundingTextDiffersBetweenSnapshots() throws {
        let fixture = try PatchFixture(source: "hello\n", insert: "!", at: 5)
        // A next snapshot whose *unchanged* region does not match the current one at all.
        let divergent = PresentationSnapshot.make(
            id: PresentationSnapshot.ID(value: 2),
            sourceRevision: SourceRevision(value: 2),
            locationGeneration: 1,
            renderedString: "different!\n",
            runs: [],
            attachments: [],
            tables: [],
            atoms: [.identity(IdentityAtom(
                projection: NSRange(location: 0, length: 11),
                source: NSRange(location: 0, length: 11),
                insertionBefore: 0,
                insertionAfter: 11
            ))],
            sourceUTF16Count: 11
        )
        let transition = PresentationTransition(
            fromSnapshotID: fixture.current.id,
            nextSnapshot: divergent,
            projectionReplacementRange: NSRange(location: 5, length: 0),
            projectionReplacement: "!",
            selectionAfter: ProjectionSelection(
                utf16: NSRange(location: 6, length: 0),
                revision: divergent.projectionRevision
            )
        )
        let patch = PresentationPatch.make(
            transition: transition,
            current: fixture.current,
            buildScope: { model, scope in
                AttributedPresentationBuilder.buildScoped(model: model, theme: MarkdownTheme(), scope: scope)
            }
        )
        #expect(patch == nil)
    }

    // Verifies: REQ-109 — a declared replacement that would run past the next snapshot refuses
    // before Foundation receives an invalid substring range.
    @Test func patchRefusesMalformedNextReplacementRange() throws {
        let fixture = try PatchFixture(source: "hello\n", insert: "!", at: 5)
        let transition = PresentationTransition(
            fromSnapshotID: fixture.current.id,
            nextSnapshot: fixture.next,
            projectionReplacementRange: NSRange(location: 5, length: 0),
            projectionReplacement: "too long",
            selectionAfter: ProjectionSelection(
                utf16: NSRange(location: 6, length: 0),
                revision: fixture.next.projectionRevision
            )
        )
        let patch = PresentationPatch.make(
            transition: transition,
            current: fixture.current,
            buildScope: { model, scope in
                AttributedPresentationBuilder.buildScoped(model: model, theme: MarkdownTheme(), scope: scope)
            }
        )
        #expect(patch == nil)
    }

    // Verifies: REQ-109 — changing text before an unchanged suffix preserves the suffix boundary
    // instead of needlessly including its first grapheme in the patch.
    @Test func changedSpanKeepsUnchangedSuffixAtBoundary() {
        let changed = PresentationPatch.changedSpan(from: "abc\ndef" as NSString, to: "def" as NSString)
        guard let ranges = changed else {
            Issue.record("expected a deletion span")
            return
        }
        #expect(ranges.0 == NSRange(location: 0, length: 4))
        #expect(ranges.1 == NSRange(location: 0, length: 0))
    }

    // Verifies: REQ-109 — source-only coordinates and node identities in a distant table do not
    // make a hidden-delimiter command refresh every intervening block.
    @Test func sourceOnlyTableChangesDoNotExpandAttributeRefreshScope() throws {
        let current = try snapshot(
            source: "**First**\n\n| Name | Value |\n| --- | --- |\n| A | B |\n",
            id: 1,
            revision: 1
        )
        let next = try snapshot(
            source: "***First***\n\n| Name | Value |\n| --- | --- |\n| A | B |\n",
            id: 2,
            revision: 2
        )
        let tableStart = try #require(next.tables.first?.utf16Range.location)
        let scope = try #require(PresentationPatch.attributeRefreshScope(current: current, next: next))

        #expect(NSMaxRange(scope) <= tableStart)
    }

    // Verifies: REQ-109 — a decoded image replacing an otherwise identical placeholder expands
    // the attribute refresh to that attachment without rewriting document characters.
    @Test func resolvedImageLocationParticipatesInAttributeRefreshScope() throws {
        let current = try snapshot(source: "![](assets/photo.png)\n", id: 1, revision: 1)
        let location = try #require(current.attachments.first?.utf16Location)
        let next = try snapshot(source: "![](assets/photo.png)\n", id: 2, revision: 1)
        let scope = try #require(
            PresentationPatch.attributeRefreshScope(
                current: current,
                next: next,
                imageRefreshLocations: [location]
            )
        )

        #expect(NSLocationInRange(location, scope))
    }

    // Verifies: REQ-109 — a decoded image can arrive with unchanged projection text and
    // semantics. Its attachment block refreshes once; a later reconciliation using the same
    // bounded-cache image performs no redundant attribute rewrite.
    @Test func resolvedImageRefreshesItsAttachmentOnlyWhenDisplayIdentityChanges() throws {
        let harness = try EditorHarness(source: "![](assets/photo.png)\n\nTrailing paragraph.\n")
        let attachment = try #require(harness.session.presentation?.attachments.first)
        harness.session.installResolvedImagesForTesting([
            attachment.nodeID: NSImage(size: NSSize(width: 20, height: 20))
        ])
        try harness.installAuthoritativeProjection()
        harness.storage.resetSpy()

        harness.coordinator.applyProjectionIfNeeded(force: false)

        #expect(harness.storage.fullReplacements == 0)
        #expect(harness.storage.characterReplacements.isEmpty)
        #expect(!harness.storage.attributeReplacements.isEmpty)
        #expect(harness.storage.attributeReplacements.allSatisfy {
            NSLocationInRange(attachment.utf16Location, $0)
                && NSMaxRange($0) < (harness.textView.string as NSString).length
        })

        harness.storage.resetSpy()
        try harness.installAuthoritativeProjection()
        harness.coordinator.applyProjectionIfNeeded(force: false)

        #expect(harness.storage.attributeReplacements.isEmpty)
    }

    // Verifies: REQ-109; ARC-Q16 — a formatting command whose rendered text is unchanged (the
    // delimiters are hidden) refreshes attributes and replaces nothing at all.
    @Test func hiddenDelimiterCommandRefreshesAttributesWithoutReplacing() async throws {
        let harness = try EditorHarness(source: "First paragraph.\n\nSecond paragraph.\n")
        await harness.settle()
        harness.storage.resetSpy()
        let controller = harness.makeCommandController()
        harness.select(NSRange(location: 0, length: 5))

        #expect(controller.perform(.bold) == .accepted)
        harness.coordinator.applyProjectionIfNeeded(force: false)

        #expect(harness.document.text.hasPrefix("**First**"))
        // Bold hides its delimiters, so the projection text is identical and no character may be
        // touched — and certainly not the whole storage.
        #expect(harness.storage.fullReplacements == 0, "formatting command replaced the whole storage")
        #expect(harness.storage.characterReplacements.isEmpty, "unchanged text was still rewritten")
        #expect(!harness.storage.attributeReplacements.isEmpty)
        #expect(
            harness.storage.attributeReplacements.allSatisfy {
                NSMaxRange($0) < (harness.textView.string as NSString).length
            },
            "one-word formatting refreshed attributes outside its semantic block"
        )
        let font = harness.textView.textStorage?
            .attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
        #expect(traits.contains(.boldFontMask), "attribute refresh did not apply the bold trait")
    }

    // Verifies: REQ-058/057/087/109; ARC-005/007/009/019 — the shared WYSIWYG command route
    // maps one ordinary paragraph exactly, rewrites only that paragraph as a list, and keeps the
    // matching presentation editable without a full-storage replacement.
    @Test func unorderedListCommandAcceptsAnOrdinaryParagraphSelection() async throws {
        let harness = try EditorHarness(source: "First paragraph.\n\nSecond paragraph.\n")
        await harness.settle()
        harness.storage.resetSpy()
        let controller = harness.makeCommandController()
        // This is the first paragraph's visible identity text; the following rendered newline is
        // synthetic paragraph structure and deliberately excluded.
        harness.select(NSRange(location: 0, length: 16))

        #expect(controller.perform(.unorderedList) == .accepted)
        harness.coordinator.applyProjectionIfNeeded(force: false)

        #expect(harness.document.text == "- First paragraph.\n\nSecond paragraph.\n")
        #expect(harness.textView.string == harness.session.presentation?.renderedString)
        #expect(harness.storage.fullReplacements == 0)
    }

    // Verifies: REQ-109; ARC-Q16 — installing a newer snapshot whose rendered text differs uses
    // one bounded patch. This is the route every formatting command and every authoritative
    // reconciliation takes once the session has installed the new snapshot; it is driven at that
    // boundary so the assertion does not depend on an individual planner's preconditions.
    @Test func newerSnapshotWithChangedTextUsesOneBoundedPatch() async throws {
        let harness = try EditorHarness(source: "First paragraph.\n\nSecond paragraph.\n")
        await harness.settle()
        harness.storage.resetSpy()

        let applied = try #require(harness.session.presentation)
        let nextSource = "First paragraph!\n\nSecond paragraph.\n"
        let index = MarkdownSourceIndex(source: nextSource, sourceVersion: applied.sourceRevision.value + 1)
        let tree = try #require(MarkdownParser.parse(nextSource, sourceVersion: applied.sourceRevision.value + 1).get())
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        harness.session.installProjectionForTesting(model, tree: tree)

        let next = try #require(harness.session.presentation)
        #expect(next.id != applied.id)
        #expect(next.renderedString != applied.renderedString)

        // IME completion and task attachment presses use force: true. A newer snapshot must
        // still patch rather than treating force as permission for a whole-storage replacement.
        harness.coordinator.applyProjectionIfNeeded(force: true)

        #expect(harness.storage.fullReplacements == 0, "a newer snapshot replaced the whole storage")
        #expect(harness.storage.characterReplacements.count == 1)
        let patched = try #require(harness.storage.characterReplacements.first)
        #expect(patched.length < (next.renderedString as NSString).length, "patch was not bounded")
        #expect(harness.textView.string == next.renderedString)
    }

    // Verifies: REQ-109 — a task-checkbox interaction uses the same bounded attribute refresh
    // route even though it asks to apply immediately.
    @Test func taskToggleRefreshesOnlyItsSemanticBlock() async throws {
        let harness = try EditorHarness(source: "- [ ] Task\n\nTrailing paragraph.\n")
        await harness.settle()
        let attachment = try #require(harness.session.presentation?.attachments.first)
        harness.storage.resetSpy()

        harness.coordinator.performTaskToggle(nodeID: attachment.nodeID)

        #expect(harness.document.text.hasPrefix("- [x] Task"))
        #expect(harness.storage.fullReplacements == 0)
        #expect(harness.storage.characterReplacements.isEmpty)
        #expect(!harness.storage.attributeReplacements.isEmpty)
        #expect(
            harness.storage.attributeReplacements.allSatisfy {
                NSMaxRange($0) < (harness.textView.string as NSString).length
            },
            "task toggle refreshed the trailing paragraph"
        )
    }

    // Verifies: REQ-109 — heading and link commands both produce same-text snapshots and refresh
    // only their selected block rather than replacing the document.
    @Test func headingAndLinkCommandsRefreshOnlyTheirSelectedBlock() async throws {
        for command in [EditorCommand.heading(2), .editLink] {
            let harness = try EditorHarness(source: "First paragraph.\n\nTrailing paragraph.\n")
            await harness.settle()
            let controller = harness.makeCommandController()
            harness.select(NSRange(location: 0, length: 5))
            harness.storage.resetSpy()

            if command == .editLink {
                #expect(controller.perform(command) == .started)
                controller.commitLink(destination: "https://example.com")
            } else {
                #expect(controller.perform(command) == .accepted)
            }
            harness.coordinator.applyProjectionIfNeeded(force: false)

            #expect(harness.storage.fullReplacements == 0)
            #expect(harness.storage.characterReplacements.isEmpty)
            #expect(!harness.storage.attributeReplacements.isEmpty)
            #expect(harness.storage.attributeReplacements.allSatisfy {
                NSMaxRange($0) < (harness.textView.string as NSString).length
            })
        }
    }

    // Verifies: REQ-109 — a real table-cell edit uses one local character patch rather than
    // replacing storage, even though table coordinates are synthetic presentation structure.
    @Test func tableCellEditUsesOneBoundedPatch() async throws {
        let harness = try EditorHarness(source: "| Name | Value |\n| --- | --- |\n| A | B |\n\nTrailing paragraph.\n")
        await harness.settle()
        let cell = try #require(harness.session.presentation?.tables.flatMap(\.cells).first {
            ($0.utf16Range.length > 0)
        })
        harness.storage.resetSpy()

        harness.typeCharacter("!", at: NSRange(location: cell.utf16Range.location, length: 0))

        #expect(harness.storage.fullReplacements == 0)
        #expect(harness.storage.characterReplacements.count == 1)
        let patch = try #require(harness.storage.characterReplacements.first)
        #expect(patch.length < (harness.textView.string as NSString).length)
    }

    // Verifies: REQ-084/109 — a real marked-text commit asks for immediate application, and its
    // new snapshot takes only bounded patches rather than a full replacement. The marked text is
    // shown in the native storage first (REQ-084 keeps composition transient but visible), then
    // the commit replaces it; every storage edit stays inside the document and never rebuilds it.
    @Test func committedCompositionUsesBoundedPatch() throws {
        let harness = try EditorHarness(source: "ab\n\nTrailing paragraph.\n")
        harness.textView.setSelectedRange(NSRange(location: 2, length: 0))
        harness.storage.resetSpy()

        harness.textView.setMarkedText(
            "日",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 2, length: 0)
        )
        harness.textView.insertText("日", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(harness.document.text.hasPrefix("ab日"))
        #expect(harness.storage.fullReplacements == 0)
        #expect(!harness.storage.characterReplacements.isEmpty)
        #expect(harness.storage.characterReplacements.allSatisfy {
            $0.length < (harness.textView.string as NSString).length
        }, "a composition storage edit was not bounded")
    }

    // Verifies: REQ-109 — a newer snapshot carrying the same text refreshes attributes and
    // replaces no characters at all, so it needs no place in the full-replacement allowlist.
    @Test func newerSnapshotWithUnchangedTextReplacesNothing() async throws {
        let harness = try EditorHarness(source: "First paragraph.\n\nSecond paragraph.\n")
        await harness.settle()
        harness.storage.resetSpy()

        let applied = try #require(harness.session.presentation)
        let source = harness.document.text
        let index = MarkdownSourceIndex(source: source, sourceVersion: applied.sourceRevision.value)
        let tree = try #require(MarkdownParser.parse(source, sourceVersion: applied.sourceRevision.value).get())
        harness.session.installProjectionForTesting(
            MarkdownProjectionModel.build(tree: tree, index: index),
            tree: tree
        )
        let next = try #require(harness.session.presentation)
        #expect(next.renderedString == applied.renderedString)

        harness.coordinator.applyProjectionIfNeeded(force: false)

        #expect(harness.storage.fullReplacements == 0)
        #expect(harness.storage.characterReplacements.isEmpty, "unchanged text was rewritten")
        #expect(harness.textView.string == next.renderedString)
    }

    // Verifies: REQ-109 — a forced application of an already-current snapshot is a no-op unless
    // storage has actually drifted; force alone is never a reason to rebuild.
    @Test func forcedCurrentSnapshotDoesNotRecoverWithoutStorageDrift() throws {
        let trace = InMemoryEditorTrace()
        let harness = try EditorHarness(source: "First paragraph.\n", trace: trace)
        harness.storage.resetSpy()

        harness.coordinator.applyProjectionIfNeeded(force: true)

        #expect(harness.storage.fullReplacements == 0)
        #expect(trace.eventsMatching {
            if case .presentationRecovered = $0 { return true }
            return false
        }.isEmpty)
    }

    // Verifies: REQ-109; ENGINEERING §7 — a full rebuild reached from a newer snapshot because
    // applied storage drifted is recorded, never silent. Without the record this path looks
    // exactly like an ordinary first application.
    @Test func driftedStorageOnNewerSnapshotIsRecorded() async throws {
        let trace = InMemoryEditorTrace()
        let harness = try EditorHarness(source: "First paragraph.\n\nSecond paragraph.\n", trace: trace)
        await harness.settle()
        let applied = try #require(harness.session.presentation)

        // Diverge applied storage from the snapshot the coordinator believes is applied, so the
        // patch's own guard must refuse.
        harness.storage.replaceCharacters(in: NSRange(location: 0, length: 5), with: "DRIFT")
        harness.storage.resetSpy()

        let nextSource = "First paragraph!\n\nSecond paragraph.\n"
        let version = applied.sourceRevision.value + 1
        let index = MarkdownSourceIndex(source: nextSource, sourceVersion: version)
        let tree = try #require(MarkdownParser.parse(nextSource, sourceVersion: version).get())
        harness.session.installProjectionForTesting(
            MarkdownProjectionModel.build(tree: tree, index: index),
            tree: tree
        )
        harness.coordinator.applyProjectionIfNeeded(force: false)

        let recovered = trace.eventsMatching {
            if case .presentationRecovered = $0 { return true }
            return false
        }
        #expect(recovered.count == 1, "drift on a newer snapshot was rebuilt without a record")
        // Storage still converges on the current snapshot.
        #expect(harness.textView.string == harness.session.presentation?.renderedString)
        if case .waitingForCurrentProjection = harness.session.wysiwygModeState.availability {
            // Expected: recovery restores storage but does not certify it for continued editing.
        } else {
            Issue.record("unprovable newer snapshot left WYSIWYG editable")
        }
        #expect(!harness.textView.isEditable, "recovery left a live native-input window")
    }

    private func snapshot(
        source: String,
        id: UInt64,
        revision: UInt64
    ) throws -> PresentationSnapshot {
        let index = MarkdownSourceIndex(source: source, sourceVersion: revision)
        guard let tree = MarkdownParser.parse(source, sourceVersion: revision).get() else {
            throw NSError(domain: "PerformanceBoundaryTests", code: 1)
        }
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        return PresentationSnapshot.from(
            model: model,
            id: PresentationSnapshot.ID(value: id),
            locationGeneration: 0,
            sourceText: source
        )
    }

    /// A real document, session, and WYSIWYG coordinator over spy-backed storage.
    @MainActor
    final class EditorHarness {
        let document = MarkdownDocument()
        let session = EditorSession()
        let coordinator: WYSIWYGEditor.Coordinator
        let textView: MarkdownWYSIWYGTextView
        let storage: SpyTextStorage

        init(source: String, trace: (any EditorTraceSink)? = nil) throws {
            if let trace { document.trace = trace }
            document.installTextForTesting(source)
            session.attach(document: document)
            session.setMode(.wysiwyg)

            let index = MarkdownSourceIndex(source: source, sourceVersion: document.sourceVersion)
            let tree = try #require(
                MarkdownParser.parse(source, sourceVersion: document.sourceVersion).get()
            )
            let model = MarkdownProjectionModel.build(tree: tree, index: index)
            session.installProjectionForTesting(model, tree: tree)

            (textView, storage) = makeSpyBackedTextView()
            coordinator = WYSIWYGEditor.Coordinator(
                document: document,
                session: session,
                placementController: ImagePlacementController()
            )
            textView.delegate = coordinator
            textView.inputCoordinator = coordinator.input
            textView.documentActions = document
            textView.session = session
            textView.adapterCoordinator = coordinator
            coordinator.textView = textView
            coordinator.applyProjectionIfNeeded(force: true)
            storage.resetSpy()
        }

        func makeCommandController() -> EditorCommandController {
            let controller = EditorCommandController()
            controller.bind(
                document: document,
                session: session,
                actionRouter: EditorActionRouter(),
                window: nil
            )
            return controller
        }

        /// Waits until the authoritative parse scheduled by `attach` has landed, so a command's
        /// selection cannot be invalidated by a reconciliation arriving mid-test. Without this the
        /// test refuses under suite load — a false failure about a real route.
        func settle() async {
            var previous = session.presentation?.id
            for _ in 0..<200 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(5))
                let current = session.presentation?.id
                if current != nil, current == previous { return }
                previous = current
            }
        }

        func installAuthoritativeProjection() throws {
            let source = document.text
            let index = MarkdownSourceIndex(source: source, sourceVersion: document.sourceVersion)
            guard let tree = MarkdownParser.parse(source, sourceVersion: document.sourceVersion).get() else {
                throw NSError(domain: "EditorHarness", code: 1)
            }
            session.installProjectionForTesting(
                MarkdownProjectionModel.build(tree: tree, index: index),
                tree: tree
            )
        }

        /// Selects a projection range belonging to the current presentation.
        func select(_ range: NSRange) {
            guard let presentation = session.presentation else { return }
            session.updateWYSIWYGModeState {
                $0.selection = ProjectionSelection(utf16: range, revision: presentation.projectionRevision)
            }
        }

        /// Drives the real native delegate callback, the one whose latency the budget describes.
        func typeCharacter(_ text: String, at range: NSRange) {
            session.updateOrigin.with(.nativeUserInput) {
                _ = coordinator.textView(
                    textView,
                    shouldChangeTextIn: range,
                    replacementString: text
                )
            }
        }

        deinit {
            MainActor.assumeIsolated { session.detach() }
        }
    }
}
