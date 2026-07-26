//
//  TestHelpers.swift
//  Markdown EditorTests
//

import Foundation
@testable import Markdown_Editor

extension Result {
    func get() -> Success? {
        if case .success(let value) = self { return value }
        return nil
    }
}

@MainActor
extension EditorSession {
    /// Test-only adapter over the typed `perform` entry point.
    @discardableResult
    func perform(
        _ command: SemanticCommand,
        selection: SemanticSelection,
        grouping groupingOverride: MutationGrouping? = nil
    ) -> SemanticEditResult {
        let editorSelection: EditorSelection
        switch selection.mode {
        case .source:
            editorSelection = .source(
                SourceSelection(utf16: selection.utf16Range, affinity: selection.affinity)
            )
        case .wysiwyg:
            guard let presentation,
                  presentation.sourceRevision.value == selection.sourceVersion else {
                return .refused(.staleVersion)
            }
            editorSelection = .projection(
                ProjectionSelection(
                    utf16: selection.utf16Range,
                    revision: presentation.projectionRevision,
                    affinity: selection.affinity
                )
            )
        }
        return perform(
            command,
            selection: editorSelection,
            expectedSourceRevision: SourceRevision(value: selection.sourceVersion),
            grouping: groupingOverride
        ).asSemanticEditResult
    }
}

extension EditorEditOutcome {
    var asSemanticEditResult: SemanticEditResult {
        switch self {
        case .accepted(let edit):
            return .mutation(edit.sourceMutation)
        case .refused(let refusal):
            return .refused(refusal.asSemantic)
        }
    }
}
