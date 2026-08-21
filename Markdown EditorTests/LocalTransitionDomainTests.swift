//
//  LocalTransitionDomainTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

@MainActor
struct LocalTransitionDomainTests {
    // Verifies: COR-71 / REQ-090/091/092 — every classifier route is executable and the
    // source-location synthetic cases selected by Stage 0 remain refusal cases.
    @Test func everyClassifierCaseHasOneDeclaredRoute() {
        let node = MarkdownNodeID(rawValue: 1)
        let routes: [LocalTransitionRoute] = [
            LocalTransitionDomain.route(for: .identityText(sourceRange: NSRange(location: 0, length: 1))),
            LocalTransitionDomain.route(for: .atomicText(
                kind: .backslashEscape,
                sourceRange: NSRange(location: 0, length: 2),
                decoded: "*"
            )),
            LocalTransitionDomain.route(for: .syntheticInsertion(
                policy: .atSourceBoundaries(before: 0, after: 2)
            )),
            LocalTransitionDomain.route(for: .syntheticInsertion(
                policy: .atSourceLocation(2)
            )),
            LocalTransitionDomain.route(for: .tableCell(
                nodeID: node,
                sourceRange: NSRange(location: 0, length: 3),
                projectionBody: NSRange(location: 0, length: 3)
            )),
            LocalTransitionDomain.route(for: .taskMarker(nodeID: node)),
            LocalTransitionDomain.route(for: .uneditable(.unsupported)),
            LocalTransitionDomain.route(for: .mixed),
            LocalTransitionDomain.route(for: .crossCell),
            LocalTransitionDomain.route(for: .ambiguous)
        ]
        #expect(routes == [.local, .local, .local, .refusal, .bounded, .refusal, .refusal, .refusal, .refusal, .refusal])
    }

    // Verifies: COR-71 / REQ-091/092 — an ordinary literal insertion uses the parser-free local
    // planner and still returns a complete source/presentation transition.
    @Test func ordinaryLiteralInsertionUsesLocalTransition() throws {
        let document = MarkdownDocument()
        document.installTextForTesting("alpha\n")
        let session = EditorSession()
        session.attach(document: document)
        let tree = try #require(MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion).get())
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: document.text, sourceVersion: document.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)
        let presentation = try #require(session.presentation)
        let selection = ProjectionSelection(
            utf16: NSRange(location: 2, length: 0),
            revision: presentation.projectionRevision
        )
        let request = EditorEditRequest(
            command: .insertText("*"),
            selection: .projection(selection),
            expectedSourceRevision: SourceRevision(value: document.sourceVersion),
            grouping: .typing
        )
        let result = LocalTransitionDomain.plan(
            request,
            snapshot: document.sourceSnapshot(),
            presentation: presentation,
            tree: tree,
            nextSnapshotID: PresentationSnapshotIDFactory().make()
        )
        guard case .accepted(let edit) = result else {
            Issue.record("local punctuation insertion refused: \(result)")
            return
        }
        #expect(edit.presentationTransition?.sourceAfter == nil)
        #expect(edit.presentationTransition?.nextSnapshot.renderedString == "al*pha\n")
        session.detach()
    }

    // Verifies: REQ-091 — collapsed backward deletion removes the preceding presented atom and
    // advances source/presentation together before another input can arrive.
    @Test func collapsedBackwardDeletionUpdatesRenderedText() throws {
        let document = MarkdownDocument()
        document.installTextForTesting("alpha\n")
        let session = EditorSession()
        session.attach(document: document)
        let tree = try #require(MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion).get())
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: document.text, sourceVersion: document.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)
        let presentation = try #require(session.presentation)
        let selection = ProjectionSelection(
            utf16: NSRange(location: 2, length: 0),
            revision: presentation.projectionRevision
        )
        let request = EditorEditRequest(
            command: .deleteBackward,
            selection: .projection(selection),
            expectedSourceRevision: SourceRevision(value: document.sourceVersion),
            grouping: .typing
        )
        let result = LocalTransitionDomain.plan(
            request,
            snapshot: document.sourceSnapshot(),
            presentation: presentation,
            tree: tree,
            nextSnapshotID: PresentationSnapshotIDFactory().make()
        )
        guard case .accepted(let edit) = result else {
            Issue.record("backward deletion refused: \(result)")
            return
        }
        #expect(edit.sourceMutation.range == NSRange(location: 1, length: 1))
        #expect(edit.presentationTransition?.projectionReplacementRange == NSRange(location: 1, length: 1))
        #expect(edit.presentationTransition?.nextSnapshot.renderedString == "apha\n")
        session.detach()
    }

    // Verifies: REQ-092 — a parser-free local route refuses a candidate that could join an
    // existing ampersand into a formal-GFM entity instead of silently changing visible meaning.
    @Test func entityFormingLiteralContextRefusesLocally() throws {
        let document = MarkdownDocument()
        document.installTextForTesting("&\n")
        let session = EditorSession()
        session.attach(document: document)
        let tree = try #require(MarkdownParser.parse(document.text, sourceVersion: document.sourceVersion).get())
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: document.text, sourceVersion: document.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)
        let presentation = try #require(session.presentation)
        let request = EditorEditRequest(
            command: .insertText("amp;"),
            selection: .projection(ProjectionSelection(
                utf16: NSRange(location: 1, length: 0),
                revision: presentation.projectionRevision
            )),
            expectedSourceRevision: SourceRevision(value: document.sourceVersion),
            grouping: .typing
        )
        let result = LocalTransitionDomain.plan(
            request,
            snapshot: document.sourceSnapshot(),
            presentation: presentation,
            tree: tree,
            nextSnapshotID: PresentationSnapshotIDFactory().make()
        )
        guard case .refused = result else {
            Issue.record("entity-forming context was accepted: \(result)")
            return
        }
        session.detach()
    }
}
