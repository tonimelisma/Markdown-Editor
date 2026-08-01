//
//  TextStorageApplierTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

@MainActor
struct TextStorageApplierTests {
    @Test func ordinaryInsertionUsesOneBoundedRangePatch() throws {
        let source = "hello\n"
        let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
        let tree = try #require(MarkdownParser.parse(source, sourceVersion: 1).get())
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        let current = PresentationSnapshot.from(
            model: model,
            id: PresentationSnapshot.ID(value: 1),
            locationGeneration: 1,
            sourceText: source
        )
        let transition = try #require(
            PresentationTransitionPlanner.identityReplacement(
                snapshot: current,
                projectionRange: NSRange(location: 5, length: 0),
                visibleReplacement: "!",
                sourceRange: NSRange(location: 5, length: 0),
                sourceReplacement: "!",
                nextSourceRevision: SourceRevision(value: 2),
                nextSourceUTF16Count: 7,
                nextSnapshotID: PresentationSnapshot.ID(value: 2),
                affinity: .downstream
            )
        )
        let built = AttributedPresentationBuilder.build(model: transition.nextSnapshot.asProjectionModel, theme: MarkdownTheme())
        let patch = try #require(PresentationPatch.make(transition: transition, current: current, builtNext: built))
        #expect(patch.currentRange == NSRange(location: 5, length: 0))
        #expect(patch.replacement.string == "!")
        #expect(patch.fromSnapshotID == current.id)
        #expect(patch.toSnapshotID == transition.nextSnapshot.id)

        let textView = MarkdownWYSIWYGTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let applier = TextStorageApplier()
        applier.applyInitialPresentation(
            AttributedPresentationBuilder.build(model: current.asProjectionModel, theme: MarkdownTheme()),
            to: textView
        )
        #expect(applier.applyPatch(patch, to: textView, expectedCurrent: current))
        #expect(textView.string == "hello!\n")
        #expect(textView.selectedRange() == NSRange(location: 6, length: 0))
    }

    @Test func patchRefusesWhenAppliedStorageIsStale() throws {
        let current = PresentationSnapshot.make(
            id: PresentationSnapshot.ID(value: 1),
            sourceRevision: SourceRevision(value: 1),
            locationGeneration: 1,
            renderedString: "one\n",
            runs: [],
            attachments: [],
            tables: [],
            atoms: [.identity(IdentityAtom(
                projection: NSRange(location: 0, length: 4),
                source: NSRange(location: 0, length: 4),
                insertionBefore: 0,
                insertionAfter: 4
            ))],
            sourceUTF16Count: 4
        )
        let next = PresentationSnapshot.make(
            id: PresentationSnapshot.ID(value: 2),
            sourceRevision: SourceRevision(value: 2),
            locationGeneration: 1,
            renderedString: "two\n",
            runs: [],
            attachments: [],
            tables: [],
            atoms: [.identity(IdentityAtom(
                projection: NSRange(location: 0, length: 4),
                source: NSRange(location: 0, length: 4),
                insertionBefore: 0,
                insertionAfter: 4
            ))],
            sourceUTF16Count: 4
        )
        let transition = PresentationTransition(
            fromSnapshotID: current.id,
            nextSnapshot: next,
            projectionReplacementRange: NSRange(location: 0, length: 4),
            projectionReplacement: "two\n",
            selectionAfter: ProjectionSelection(utf16: NSRange(location: 0, length: 0), revision: next.projectionRevision)
        )
        let built = AttributedPresentation(
            attributed: NSAttributedString(string: "two\n"),
            attachmentNodes: [:],
            decorations: []
        )
        let patch = try #require(PresentationPatch.make(transition: transition, current: current, builtNext: built))
        let textView = MarkdownWYSIWYGTextView(frame: .zero)
        textView.string = "stale\n"
        #expect(!TextStorageApplier().applyPatch(patch, to: textView, expectedCurrent: current))
    }
}
