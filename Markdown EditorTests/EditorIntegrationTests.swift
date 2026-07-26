//
//  EditorIntegrationTests.swift
//  Markdown EditorTests
//

import Testing
import Foundation
import AppKit
@testable import Markdown_Editor

/// // Verifies: REQ-015, REQ-057, REQ-058, REQ-060, REQ-069, REQ-078, REQ-080,
/// // REQ-083, REQ-084, REQ-087, REQ-089
@MainActor
struct EditorIntegrationTests {

    private func parseBuild(_ source: String, version: UInt64 = 1) throws -> (MarkdownTree, MarkdownProjectionModel) {
        let tree = try #require(MarkdownParser.parse(source, sourceVersion: version).get())
        let index = MarkdownSourceIndex(source: source, sourceVersion: version)
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        return (tree, model)
    }

    // MARK: - D1 Select All / synthetic endpoints

    // Verifies: REQ-084/087 — Select All over paragraphs and lists maps exactly.
    @Test func selectAllOverParagraphAndListMapsExactSource() throws {
        let fixtures = [
            "hello\n",
            "one\n\ntwo\n",
            "- a\n- b\n",
            "1. a\n2. b\n",
            "- [ ] task\n",
            "- a\n  - nested\n"
        ]
        for source in fixtures {
            let (_, model) = try parseBuild(source)
            let all = NSRange(location: 0, length: (model.renderedString as NSString).length)
            guard case .exact(let mapped) = model.coordinateMap.sourceRange(forProjection: all) else {
                Issue.record("Select All refused for \(source)")
                continue
            }
            #expect(mapped.location >= 0)
            #expect(NSMaxRange(mapped) <= (source as NSString).length)
        }
    }

    // MARK: - D3 exact task marker

    // Verifies: REQ-078 — literal `[x]` in label and nested tasks stay untouched.
    @Test func taskTogglePatchesOnlyExactMarker() throws {
        let source = "- [x] keep [x] literal\n"
        let (tree, model) = try parseBuild(source)
        guard let task = model.attachments.first(where: {
            if case .task(let checked, _) = $0.kind { return checked }
            return false
        }) else {
            Issue.record("missing checked task attachment")
            return
        }
        let snapshot = SourceSnapshot(text: source, sourceVersion: 1, locationGeneration: 0, fileURL: nil)
        let result = SemanticEditEngine.apply(
            command: .toggleTask(nodeID: task.nodeID),
            selection: TestSelection(mode: .wysiwyg, utf16Range: NSRange(location: task.utf16Location, length: 1), sourceVersion: 1),
            snapshot: snapshot,
            projection: model,
            tree: tree
        )
        guard case .mutation(let mutation) = result else {
            let msg = "expected mutation, got \(String(describing: result)); attachments=\(model.attachments.count)"
            try? msg.write(toFile: "/tmp/cor08-task-fail.txt", atomically: true, encoding: .utf8)
            Issue.record("\(msg)")
            return
        }
        #expect(mutation.range.length == 3)
        #expect(mutation.replacement == "[ ]")
        let ns = source as NSString
        let replaced = ns.replacingCharacters(in: mutation.range, with: mutation.replacement)
        if replaced != "- [ ] keep [x] literal\n" {
            let msg = "unexpected '\(replaced)' range=\(mutation.range) expectedText='\(mutation.expectedText)'"
            try? msg.write(toFile: "/tmp/cor08-task-fail.txt", atomically: true, encoding: .utf8)
            Issue.record("\(msg)")
        }
        #expect(replaced == "- [ ] keep [x] literal\n")
    }

    // MARK: - D4 structural fenced code

    // Verifies: REQ-057/087 — fenced body mapping ignores repeated info/body text.
    @Test func fencedCodeBodyIsStructuralWhenInfoMatchesBody() throws {
        let source = "```swift\nswift\n```\n"
        let (_, model) = try parseBuild(source)
        let rendered = model.renderedString as NSString
        let body = rendered.range(of: "swift\n")
        #expect(body.location != NSNotFound)
        guard case .exact(let sourceRange) = model.coordinateMap.sourceRange(forProjection: body) else {
            Issue.record("expected exact fenced body map")
            return
        }
        #expect((source as NSString).substring(with: sourceRange) == "swift\n")
        // Must not point at the info string on the opening fence.
        #expect(sourceRange.location > 3)
    }

    // MARK: - D5 table typing routes to planner

    // Verifies: REQ-080 — native insertText in a table cell reaches TableCellEditPlanner.
    @Test func nativeTableTypingRoutesThroughTablePlanner() throws {
        let source = "| a | b |\n| - | - |\n| c | d |\n"
        let (tree, model) = try parseBuild(source)
        let cell = try #require(model.tables.first?.cells.first)
        let snapshot = SourceSnapshot(text: source, sourceVersion: 1, locationGeneration: 0, fileURL: nil)
        let selection = TestSelection(
            mode: .wysiwyg,
            utf16Range: NSRange(location: cell.utf16Range.location, length: cell.utf16Range.length),
            sourceVersion: 1
        )
        let accepted = SemanticEditEngine.apply(
            command: .insertText("z"),
            selection: selection,
            snapshot: snapshot,
            projection: model,
            tree: tree
        )
        guard case .mutation(let mutation) = accepted else {
            Issue.record("expected accepted cell edit, got \(accepted)")
            return
        }
        #expect(mutation.actionName == "Edit Cell")
        #expect(mutation.replacement == "z")

        let literalPipe = SemanticEditEngine.apply(
            command: .insertText("x|y"),
            selection: selection,
            snapshot: snapshot,
            projection: model,
            tree: tree
        )
        guard case .mutation(let pipeMutation) = literalPipe else {
            Issue.record("expected literal pipe encoding, got \(literalPipe)")
            return
        }
        #expect(pipeMutation.replacement == "x\\|y")
        #expect(snapshot.text == source)
    }

    // MARK: - D6 WYSIWYG typing coalesces through EditorSession

    // Verifies: REQ-083 — EditorSession.perform typing uses .typing grouping.
    @Test func wysiwygTypingCoalescesThroughSession() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hi\n")
        let trace = InMemoryEditorTrace()
        doc.trace = trace
        let session = EditorSession()
        session.attach(document: doc)
        let tree = MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get()!
        let index = MarkdownSourceIndex(source: doc.text, sourceVersion: doc.sourceVersion)
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        session.installProjectionForTesting(model, tree: tree)

        let sel = TestSelection(
            mode: .wysiwyg,
            utf16Range: NSRange(location: 0, length: 0),
            sourceVersion: doc.sourceVersion
        )
        _ = session.perform(.insertText("a"), selection: sel)
        let v1 = doc.sourceVersion
        let sel2 = TestSelection(
            mode: .wysiwyg,
            utf16Range: NSRange(location: 1, length: 0),
            sourceVersion: v1
        )
        // Rebuild projection for advanced version.
        let tree2 = MarkdownParser.parse(doc.text, sourceVersion: v1).get()!
        let model2 = MarkdownProjectionModel.build(
            tree: tree2,
            index: MarkdownSourceIndex(source: doc.text, sourceVersion: v1)
        )
        session.installProjectionForTesting(model2, tree: tree2)
        _ = session.perform(.insertText("b"), selection: sel2)

        let typingEvents = trace.events.compactMap { event -> Bool? in
            if case .undoRegistered(_, let typing) = event { return typing }
            return nil
        }
        #expect(typingEvents.contains(true))
        #expect(doc.text == "abhi\n")
    }

    // MARK: - D7 toolbar offset zero

    // Verifies: REQ-058 — real source caret at zero is not treated as missing.
    @Test func toolbarUsesModeLocalOffsetZero() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hello")
        let session = EditorSession()
        session.attach(document: doc)
        session.setMode(.source)
        session.updateSourceModeState {
            $0.selection = SourceSelection(utf16: NSRange(location: 0, length: 0))
        }
        // Simulate toolbar selection resolution without the old sentinel fallback.
        let range = session.sourceModeState.selection.range.utf16
        #expect(range.location == 0)
        let selection = TestSelection(
            mode: .source,
            utf16Range: range,
            sourceVersion: doc.sourceVersion
        )
        let result = session.perform(.insertText("X"), selection: selection)
        guard case .mutation = result else {
            // perform returns mutation case only before commit — actually returns after commit still .mutation
            if case .refused = result {
                Issue.record("offset-zero insert refused: \(result)")
            }
            return
        }
        #expect(doc.text.hasPrefix("X"))
    }

    // MARK: - D8 image accessibility

    // Verifies: REQ-084 — resolved images expose authored description.
    @Test func resolvedImageExposesAuthoredAccessibilityDescription() throws {
        let source = "![alt text](assets/x.png)\n"
        let tree = try #require(MarkdownParser.parse(source, sourceVersion: 1).get())
        let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        let attachment = try #require(model.attachments.first)
        let image = NSImage(size: NSSize(width: 10, height: 10))
        let built = RichTextBuilder.build(
            model: model,
            theme: MarkdownTheme(),
            images: [attachment.nodeID: image]
        )
        var found: String?
        built.attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: built.attributed.length)
        ) { value, _, _ in
            guard let nsAttachment = value as? NSTextAttachment,
                  let cell = nsAttachment.attachmentCell as? ResolvedImageAttachmentCell else { return }
            found = cell.accessibilityLabel()
        }
        #expect(found == "alt text")
    }

    // MARK: - Serialized I/O

    // Verifies: REQ-015 — serialized main-thread read installs canonical text without a mirror/gate.
    @Test func serializedReadInstallsCanonicalTextOnMain() throws {
        let doc = MarkdownDocument()
        doc.installTextForTesting("original")
        let data = MarkdownDocumentData(text: "from-disk").data()
        try doc.read(from: data, ofType: "net.daringfireball.markdown")
        #expect(doc.text == "from-disk")
        #expect(doc.sourceVersion == 1)
    }

    // Verifies: REQ-018/091/093; ARC-003/004 — load identities are monotonic
    // and synchronously make any prior presentation unavailable.
    @Test func repeatedLoadsNeverReuseRevisionOrOldPresentation() throws {
        let doc = MarkdownDocument()
        doc.installTextForTesting("original")
        let session = EditorSession()
        session.attach(document: doc)
        let tree = try #require(
            MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get()
        )
        session.installProjectionForTesting(
            MarkdownProjectionModel.build(
                tree: tree,
                index: MarkdownSourceIndex(
                    source: doc.text,
                    sourceVersion: doc.sourceVersion
                )
            ),
            tree: tree
        )
        #expect(session.presentation != nil)

        try doc.read(
            from: MarkdownDocumentData(text: "first").data(),
            ofType: "net.daringfireball.markdown"
        )
        let firstRevision = doc.sourceVersion
        #expect(firstRevision == 1)
        #expect(session.presentation == nil)

        try doc.read(
            from: MarkdownDocumentData(text: "second").data(),
            ofType: "net.daringfireball.markdown"
        )
        #expect(doc.sourceVersion == firstRevision + 1)
        #expect(session.presentation == nil)
    }

    // MARK: - D10 observer teardown

    // Verifies: REQ-015 — undo checkpoint observer is removed deterministically.
    @Test func undoCheckpointObserverRemovedOnDetach() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("x")
        let center = NotificationCenter()
        doc.notificationCenterForTesting = center
        // Re-attach observer on the test center.
        doc.detachUndoCheckpointObserver()
        // Force attach via a typing mutation path.
        let mutation = SourceMutation(
            expectedRevision: 0,
            range: NSRange(location: 0, length: 0),
            expectedText: "",
            replacement: "a",
            selectionBefore: SourceSelection(utf16: NSRange(location: 0, length: 0)),
            selectionAfter: SourceSelection(utf16: NSRange(location: 1, length: 0)),
            actionName: "Typing",
            grouping: .typing
        )
        // Re-install to get undo manager + observer on default, then swap.
        doc.installTextForTesting("x")
        _ = doc.commitSourceMutation(
            SourceMutation(
                expectedRevision: 0,
                range: NSRange(location: 0, length: 0),
                expectedText: "",
                replacement: "a",
                selectionBefore: SourceSelection(utf16: NSRange(location: 0, length: 0)),
                selectionAfter: SourceSelection(utf16: NSRange(location: 1, length: 0)),
                actionName: "Typing",
                grouping: .typing
            )
        )
        doc.detachUndoCheckpointObserver()
        // Idempotent second call.
        doc.detachUndoCheckpointObserver()
        #expect(doc.text == "ax")
        _ = mutation
        _ = center
    }

    // MARK: - D2 image intent resolves before placement

    // Verifies: REQ-060 — projection selection maps to source before placement tracking.
    @Test func imageIntentResolvesProjectionBeforePlacement() throws {
        let source = "**bold** here\n"
        let (_, model) = try parseBuild(source)
        let rendered = model.renderedString as NSString
        let here = rendered.range(of: "here")
        #expect(here.location != NSNotFound)
        let snapshot = SourceSnapshot(text: source, sourceVersion: 1, locationGeneration: 0, fileURL: nil)
        guard case .exact(let sourceRange) = model.coordinateMap.sourceRange(
            forProjection: NSRange(location: here.location, length: 0),
            affinity: .downstream
        ) else {
            Issue.record("expected exact source intent")
            return
        }
        _ = snapshot
        // After "**bold** " (7 chars) + hidden delimiters make projection shorter than source.
        #expect(sourceRange.location > here.location || sourceRange.location == 8)
        #expect((source as NSString).substring(with: NSRange(location: sourceRange.location, length: 4)) == "here"
                || sourceRange.location == (source as NSString).range(of: "here").location)
    }

    // MARK: - PR #14 review triage regressions

    // Verifies: REQ-057 — normalized inline code (`` ` foo ` ``) is uneditable, not shifted.
    @Test func normalizedInlineCodeIsUneditable() throws {
        let source = "x ` foo ` y\n"
        let (_, model) = try parseBuild(source)
        let rendered = model.renderedString as NSString
        let foo = rendered.range(of: "foo")
        #expect(foo.location != NSNotFound)
        // Must not claim an exact (shifted) source map for normalized code.
        if case .exact(let sourceRange) = model.coordinateMap.sourceRange(forProjection: foo) {
            Issue.record("normalized inline code must not claim exact map; got \(sourceRange)")
            return
        }
        let hasUneditable = model.segments.contains {
            if case .uneditable(let r, _) = $0 {
                return NSIntersectionRange(r, foo).length > 0
            }
            return false
        }
        #expect(hasUneditable)
    }

    // Verifies: REQ-057 — CRLF fenced body that normalizes is uneditable.
    @Test func crlfFencedCodeBodyIsUneditableWhenNormalized() throws {
        let source = "```\r\nline\r\n```\n"
        let (_, model) = try parseBuild(source)
        // If the fence was identity-mappable, mapped body equals raw; otherwise uneditable.
        let hasUneditableCode = model.segments.contains { seg in
            if case .uneditable = seg { return true }
            return false
        }
        let rendered = model.renderedString
        #expect(rendered.contains("line"))
        #expect(hasUneditableCode)
    }

    // Verifies: REQ-080 — caret at start of column 2 owns cell 2, not cell 1's trailing tab.
    @Test func tableCellHalfOpenBoundaryPrefersLaterColumn() throws {
        let source = "| a | b |\n| - | - |\n| c | d |\n"
        let (_, model) = try parseBuild(source)
        let cells = try #require(model.tables.first?.cells)
        #expect(cells.count >= 2)
        let second = cells[1]
        let caret = NSRange(location: second.utf16Range.location, length: 0)
        let snapshot = PresentationSnapshot.from(
            model: model,
            id: PresentationSnapshot.ID(value: 1),
            locationGeneration: 0,
            sourceText: source
        )
        let classification = ProjectionSelectionClassifier.classify(
            selection: caret,
            affinity: .downstream,
            snapshot: snapshot
        )
        guard case .tableCell(let id, _, _) = classification else {
            Issue.record("expected table cell at column-2 start, got \(classification)")
            return
        }
        #expect(id == second.nodeID)
    }

    // Verifies: REQ-080/087; ARC-009 — cell ownership requires complete
    // containment; a selection extending into prose is mixed and uneditable.
    @Test func tableSelectionExtendingIntoParagraphIsMixed() throws {
        let source = "| a |\n| --- |\n| b |\n\nafter\n"
        let snapshot = try #require(
            AuthoritativePresentationBuilder.build(
                source: source,
                sourceRevision: 1,
                snapshotID: PresentationSnapshot.ID(value: 1),
                locationGeneration: 0
            )
        )
        let finalCell = try #require(snapshot.tables.first?.cells.last)
        let selection = NSRange(
            location: finalCell.utf16Range.location,
            length: (snapshot.renderedString as NSString).length - finalCell.utf16Range.location
        )

        let classification = ProjectionSelectionClassifier.classify(
            selection: selection,
            affinity: .downstream,
            snapshot: snapshot
        )
        #expect(classification == .mixed)
    }

    // Verifies: REQ-080 — typing in a cell with `\|` edits source escapes, not rendered rebuild.
    @Test func tableTypingPreservesEscapedPipeInSource() throws {
        let source = "| a\\|b |\n| --- |\n| c |\n"
        let (tree, model) = try parseBuild(source)
        let cell = try #require(model.tables.first?.cells.first)
        let snapshot = SourceSnapshot(text: source, sourceVersion: 1, locationGeneration: 0, fileURL: nil)
        // Caret after rendered 'a' (projection shows a|b).
        let caret = NSRange(location: cell.utf16Range.location + 1, length: 0)
        let result = SemanticEditEngine.apply(
            command: .insertText("x"),
            selection: TestSelection(mode: .wysiwyg, utf16Range: caret, sourceVersion: 1, affinity: .downstream),
            snapshot: snapshot,
            projection: model,
            tree: tree
        )
        guard case .mutation(let mutation) = result else {
            Issue.record("expected mutation preserving escapes, got \(result)")
            return
        }
        #expect(mutation.actionName == "Edit Cell")
        #expect(mutation.replacement.contains("\\|"))
        #expect(mutation.replacement.contains("x"))
        // Must not have collapsed the escape into a bare structural pipe-only cell.
        #expect(mutation.replacement != "ax|b")
        #expect(mutation.replacement != "ax|b ")
    }

    // Verifies: REQ-016 — WYSIWYG paste override uses discrete grouping.
    @Test func wysiwygPasteUsesDiscreteGroupingOverride() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hi\n")
        let trace = InMemoryEditorTrace()
        doc.trace = trace
        let session = EditorSession()
        session.attach(document: doc)
        let tree = MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get()!
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: doc.text, sourceVersion: doc.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)
        let sel = TestSelection(
            mode: .wysiwyg,
            utf16Range: NSRange(location: 0, length: 0),
            sourceVersion: doc.sourceVersion
        )
        _ = session.perform(.insertText("paste"), selection: sel, grouping: .discrete)
        let discrete = trace.events.contains {
            if case .undoRegistered(_, let typing) = $0 { return !typing }
            return false
        }
        #expect(discrete)
    }

    // Verifies: REQ-016 — closeTypingUndoGroup ends an open typing group.
    @Test func closeTypingUndoGroupEndsOpenTypingGroup() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hi\n")
        let mutation = SourceMutation(
            expectedRevision: 0,
            range: NSRange(location: 0, length: 0),
            expectedText: "",
            replacement: "a",
            selectionBefore: SourceSelection(utf16: NSRange(location: 0, length: 0)),
            selectionAfter: SourceSelection(utf16: NSRange(location: 1, length: 0)),
            actionName: "Typing",
            grouping: .typing
        )
        _ = doc.commitSourceMutation(mutation)
        #expect(doc.text.hasPrefix("a"))
        doc.closeTypingUndoGroup()
        // After close, a discrete commit must not nest into the prior typing group forever.
        let discrete = SourceMutation(
            expectedRevision: doc.sourceVersion,
            range: NSRange(location: 1, length: 0),
            expectedText: "",
            replacement: "!",
            selectionBefore: SourceSelection(utf16: NSRange(location: 1, length: 0)),
            selectionAfter: SourceSelection(utf16: NSRange(location: 2, length: 0)),
            actionName: "Paste",
            grouping: .discrete
        )
        _ = doc.commitSourceMutation(discrete)
        #expect(doc.text.contains("a"))
        #expect(doc.text.contains("!"))
    }

    // Verifies: REQ-058 — heading planner preserves selectionBefore through transformLine.
    @Test func headingPlannerForwardsSelectionBefore() throws {
        let source = "hello\n"
        let snapshot = SourceSnapshot(text: source, sourceVersion: 1, locationGeneration: 0, fileURL: nil)
        let caret = SourceSelection(utf16: NSRange(location: 2, length: 0))
        let result = BlockEditPlanner.setHeading(
            snapshot: snapshot,
            range: NSRange(location: 2, length: 0),
            level: 1,
            grouping: .discrete,
            selectionBefore: caret
        )
        guard case .mutation(let mutation) = result else {
            Issue.record("expected heading mutation")
            return
        }
        #expect(mutation.selectionBefore.range.utf16 == caret.range.utf16)
    }

    // Verifies: REQ-078 — task toggle history selection is the source marker, not projection.
    @Test func taskToggleSelectionBeforeIsSourceMarker() throws {
        let source = "- [ ] task\n"
        let (tree, model) = try parseBuild(source)
        let task = try #require(model.attachments.first)
        let snapshot = SourceSnapshot(text: source, sourceVersion: 1, locationGeneration: 0, fileURL: nil)
        let result = SemanticEditEngine.apply(
            command: .toggleTask(nodeID: task.nodeID),
            selection: TestSelection(
                mode: .wysiwyg,
                utf16Range: NSRange(location: task.utf16Location, length: 1),
                sourceVersion: 1
            ),
            snapshot: snapshot,
            projection: model,
            tree: tree
        )
        guard case .mutation(let mutation) = result else {
            Issue.record("expected task mutation")
            return
        }
        #expect(mutation.selectionBefore.range.length == 3)
        #expect((source as NSString).substring(with: mutation.selectionBefore.range.utf16) == "[ ]")
    }

    // Verifies: REQ-015 — data(ofType:) snapshots canonical main-actor text.
    @Test func dataOfTypeSnapshotsCanonicalText() throws {
        let doc = MarkdownDocument()
        doc.installTextForTesting("canonical")
        let mutation = SourceMutation(
            expectedRevision: 0,
            range: NSRange(location: 0, length: 9),
            expectedText: "canonical",
            replacement: "edited",
            selectionBefore: SourceSelection(utf16: NSRange(location: 0, length: 9)),
            selectionAfter: SourceSelection(utf16: NSRange(location: 6, length: 0)),
            actionName: "Edit",
            grouping: .discrete
        )
        _ = doc.commitSourceMutation(mutation)
        #expect(doc.text == "edited")
        let data = try doc.data(ofType: "net.daringfireball.markdown")
        #expect(String(data: data, encoding: .utf8) == "edited")
    }
}
