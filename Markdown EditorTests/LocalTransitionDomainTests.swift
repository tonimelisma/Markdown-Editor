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
    // Verifies: COR-71 / REQ-090 — every classifier case is assigned by the closed route matrix.
    @Test func everyClassifierCaseHasOneDeclaredRoute() {
        let declared: Set<LocalTransitionClass> = [
            .identityText, .atomicText, .syntheticInsertion, .tableCell, .taskMarker,
            .uneditable, .mixed, .crossCell, .ambiguous
        ]
        #expect(Set(LocalTransitionClass.allCases) == declared)
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
}
