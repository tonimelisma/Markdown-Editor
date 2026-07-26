//
//  AuthoritativePresentationBuilder.swift
//  Markdown Editor
//

import Foundation

/// Builds complete authoritative presentations away from the main actor.
///
/// Semantic formatting commands may wait for this exact result, but parser, index, and
/// projection work execute on this private worker queue. Ordinary typing uses local transitions.
/// // REQ-085; ARC-Q06
nonisolated enum AuthoritativePresentationBuilder {
    static func build(
        source: String,
        sourceRevision: UInt64,
        snapshotID: PresentationSnapshot.ID,
        locationGeneration: UInt64
    ) -> PresentationSnapshot? {
        EditorSemanticWorker.sync {
            let index = MarkdownSourceIndex(source: source, sourceVersion: sourceRevision)
            guard case .success(let tree) = MarkdownParser.parse(
                source,
                sourceVersion: sourceRevision
            ) else {
                return nil
            }
            let model = MarkdownProjectionModel.build(tree: tree, index: index)
            return PresentationSnapshot.from(
                model: model,
                id: snapshotID,
                locationGeneration: locationGeneration,
                sourceText: source
            )
        }
    }
}
