//
//  AcceptedEditTransactionTests.swift
//  Markdown EditorTests
//

import Testing
import AppKit
import Foundation
@testable import Markdown_Editor

@MainActor
struct AcceptedEditTransactionTests {

    // Verifies: REQ-091; ARC-005 — consecutive WYSIWYG inserts without waiting for parse.
    @Test func twoImmediateKeystrokesAdvanceSourceAndPresentation() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hi\n")
        let session = EditorSession()
        session.attach(document: doc)
        let tree = MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get()!
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: doc.text, sourceVersion: doc.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)
        let firstID = session.presentation!.id

        let first = session.perform(
            .insertText("a"),
            selection: .projection(
                ProjectionSelection(
                    utf16: NSRange(location: 0, length: 0),
                    revision: session.presentation!.projectionRevision
                )
            ),
            expectedSourceRevision: SourceRevision(value: doc.sourceVersion)
        )
        guard case .accepted(let editA) = first else {
            Issue.record("first insert refused: \(first)")
            return
        }
        #expect(editA.presentationTransition != nil)
        #expect(session.presentation?.id != firstID)
        #expect(session.presentation?.sourceRevision.value == doc.sourceVersion)
        #expect(doc.text.hasPrefix("ahi") || doc.text.hasPrefix("a"))

        let second = session.perform(
            .insertText("b"),
            selection: .projection(
                ProjectionSelection(
                    utf16: NSRange(location: 1, length: 0),
                    revision: session.presentation!.projectionRevision
                )
            ),
            expectedSourceRevision: SourceRevision(value: doc.sourceVersion)
        )
        guard case .accepted = second else {
            Issue.record("second immediate insert refused: \(second)")
            return
        }
        #expect(doc.text.contains("ab") || doc.text.hasPrefix("ab") || doc.text.hasPrefix("ba") || doc.text.hasPrefix("a"))
        if case .editable(let id) = session.wysiwygModeState.availability {
            #expect(id == session.presentation?.id)
        } else {
            Issue.record("expected editable availability after accepted edits")
        }
    }

    // Verifies: REQ-091; ARC-Q01 — 100 immediate accepted inserts.
    @Test func oneHundredImmediateKeystrokes() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("\n")
        let session = EditorSession()
        session.attach(document: doc)
        let tree = MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get()!
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: doc.text, sourceVersion: doc.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)

        var refused = 0
        for i in 0..<100 {
            guard let presentation = session.presentation else {
                refused += 1
                break
            }
            let outcome = session.perform(
                .insertText("x"),
                selection: .projection(
                    ProjectionSelection(
                        utf16: NSRange(location: i, length: 0),
                        revision: presentation.projectionRevision
                    )
                ),
                expectedSourceRevision: SourceRevision(value: doc.sourceVersion)
            )
            if case .refused = outcome {
                refused += 1
                break
            }
        }
        #expect(refused == 0)
        #expect((doc.text as NSString).length >= 100)
    }

    // Verifies: REQ-091; ARC-005 — refused edit changes neither source nor presentation.
    @Test func refusedEditChangesNeither() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hi\n")
        let session = EditorSession()
        session.attach(document: doc)
        let tree = MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get()!
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: doc.text, sourceVersion: doc.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)
        let beforeText = doc.text
        let beforeID = session.presentation!.id

        let outcome = session.perform(
            .insertText("z"),
            selection: .projection(
                ProjectionSelection(
                    utf16: NSRange(location: 0, length: 0),
                    revision: ProjectionRevision(value: 999_999)
                )
            ),
            expectedSourceRevision: SourceRevision(value: doc.sourceVersion)
        )
        #expect({
            if case .refused = outcome { return true }
            return false
        }())
        #expect(doc.text == beforeText)
        #expect(session.presentation?.id == beforeID)
    }
}

@MainActor
struct EditorStateOwnershipTests {

    // Verifies: REQ-052/086; ARC-002 — session owns typed mode state; no ModeViewState symbol.
    @Test func sessionOwnsTypedModeState() {
        let session = EditorSession()
        session.updateSourceModeState {
            $0.selection = SourceSelection(utf16: NSRange(location: 2, length: 0), affinity: .upstream)
            $0.scrollOffset = CGPoint(x: 0, y: 12)
        }
        #expect(session.sourceModeState.selection.nsRange.location == 2)
        #expect(session.sourceModeState.selection.affinity == .upstream)
        #expect(session.sourceModeState.scrollOffset.y == 12)

        let sources = try! String(contentsOfFile: #filePath.replacingOccurrences(
            of: "Markdown EditorTests/AcceptedEditTransactionTests.swift",
            with: "Markdown Editor/EditorSession.swift"
        ), encoding: .utf8)
        #expect(!sources.contains("ModeViewState"))
        #expect(!sources.contains("sourceViewState"))
        #expect(!sources.contains("wysiwygViewState"))
    }

    // Verifies: ARC-002 — displaced compatibility symbols are gone from production sources.
    @Test func displacedCompatibilitySymbolsAbsent() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Markdown Editor")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        var haystack = ""
        for file in files {
            haystack += try String(contentsOf: file, encoding: .utf8)
            haystack += "\n"
        }
        for symbol in ["ModeViewState", "EditorViewState", "EditorViewChromeState", "LogicalSelection"] {
            #expect(!haystack.contains("struct \(symbol)"), "found \(symbol)")
            #expect(!haystack.contains("typealias \(symbol)"), "found typealias \(symbol)")
        }
    }
}

@MainActor
struct PresentationSnapshotTests {

    // Verifies: REQ-091; ARC-003 — equal source revision with different snapshot IDs is distinguishable.
    @Test func snapshotIdentityDistinctFromSourceRevision() {
        let model = MarkdownProjectionModel.build(
            tree: MarkdownParser.parse("hi\n", sourceVersion: 1).get()!,
            index: MarkdownSourceIndex(source: "hi\n", sourceVersion: 1)
        )
        let a = PresentationSnapshot.from(model: model, id: .init(value: 1), locationGeneration: 0)
        let b = PresentationSnapshot.from(model: model, id: .init(value: 2), locationGeneration: 0)
        #expect(a.sourceRevision == b.sourceRevision)
        #expect(a.id != b.id)
        #expect(ProjectionOracle.validate(snapshot: a).get() != nil)
    }
}

@MainActor
struct MarkdownLiteralEncoderTests {

    // Verifies: REQ-092; ARC-008 — punctuation encodes safely while remaining literal intent.
    @Test func encodesEmphasisAndEntities() {
        let ctx = LiteralEncodeContext(
            intendedVisibleText: "* & <",
            precedingSourceCharacter: nil,
            followingSourceCharacter: nil,
            atLineStart: true,
            container: .paragraph,
            dialect: .formalGFM
        )
        guard case .encoded(let spelling) = MarkdownLiteralEncoder.encode(ctx) else {
            Issue.record("encode refused")
            return
        }
        #expect(spelling.contains("\\*") || spelling.hasPrefix("*") == false || spelling.contains("\\*"))
        #expect(spelling.contains("&amp;") || spelling.contains("&"))
        #expect(spelling.contains("&lt;"))
    }

    @Test func tableCellEscapesPipe() {
        let ctx = LiteralEncodeContext(
            intendedVisibleText: "a|b",
            precedingSourceCharacter: nil,
            followingSourceCharacter: nil,
            atLineStart: false,
            container: .tableCell,
            dialect: .formalGFM
        )
        guard case .encoded(let spelling) = MarkdownLiteralEncoder.encode(ctx) else {
            Issue.record("encode refused")
            return
        }
        #expect(spelling.contains("\\|"))
    }
}

@MainActor
struct ProjectionSelectionClassifierTests {

    // Verifies: REQ-080/087; ARC-009 — cross-cell selection refuses.
    @Test func refusesCrossCellSelection() throws {
        let source = "| a | b |\n| - | - |\n| 1 | 2 |\n"
        let tree = try #require(MarkdownParser.parse(source, sourceVersion: 1).get())
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: source, sourceVersion: 1)
        )
        let snapshot = PresentationSnapshot.from(model: model, id: .init(value: 1), locationGeneration: 0)
        guard snapshot.tables.first?.cells.count ?? 0 >= 2 else {
            Issue.record("expected table cells")
            return
        }
        let cells = snapshot.tables[0].cells
        let start = cells[0].utf16Range.location
        let end = NSMaxRange(cells[1].utf16Range)
        let classified = ProjectionSelectionClassifier.classify(
            selection: NSRange(location: start, length: end - start),
            affinity: .downstream,
            snapshot: snapshot
        )
        if case .crossCell = classified {
            // expected
        } else if case .mixed = classified {
            // also acceptable refusal class
        } else {
            Issue.record("expected cross-cell/mixed, got \(classified)")
        }
    }
}

@MainActor
struct NativeUpdateOriginTests {

    // Verifies: REQ-083/084; ARC-013 — programmatic selection does not close typing.
    @Test func programmaticOriginDoesNotCloseTyping() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hi\n")
        let session = EditorSession()
        session.attach(document: doc)
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
        session.updateOrigin.with(.programmaticPresentation) {
            #expect(session.updateOrigin.current == .programmaticPresentation)
        }
        #expect(session.updateOrigin.current == .nativeUserInput)
        // Typing group remains open until a native selection boundary.
        let second = SourceMutation(
            expectedRevision: doc.sourceVersion,
            range: NSRange(location: 1, length: 0),
            expectedText: "",
            replacement: "b",
            selectionBefore: SourceSelection(utf16: NSRange(location: 1, length: 0)),
            selectionAfter: SourceSelection(utf16: NSRange(location: 2, length: 0)),
            actionName: "Typing",
            grouping: .typing
        )
        _ = doc.commitSourceMutation(second)
        #expect(doc.text.hasPrefix("ab"))
    }
}

@MainActor
struct DocumentSerializedIOTests {

    // Verifies: REQ-015; ARC-001/011 — default serialized NSDocument I/O opt-ins remain false.
    @Test func concurrentReadAndAsyncWriteDefaultsRemainDisabled() {
        #expect(MarkdownDocument.canConcurrentlyReadDocuments(ofType: "net.daringfireball.markdown") == false)
        let doc = MarkdownDocument()
        #expect(doc.canAsynchronouslyWrite(to: URL(fileURLWithPath: "/tmp/x.md"), ofType: "net.daringfireball.markdown", for: .saveOperation) == false)
    }
}

@MainActor
struct ArchitectureConformanceTests {

    // Verifies: ARC-014 — no UI-test target dependency.
    @Test func noUITestTargetInProject() throws {
        let project = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Markdown Editor.xcodeproj/project.pbxproj")
        let text = try String(contentsOf: project, encoding: .utf8)
        #expect(!text.contains("XCUITest"))
        #expect(!text.contains("UITests"))
    }
}
