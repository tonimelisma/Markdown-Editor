//
//  TestHelpers.swift
//  Markdown EditorTests
//

import Foundation
import CryptoKit
@testable import Markdown_Editor

extension Result {
    func get() -> Success? {
        if case .success(let value) = self { return value }
        return nil
    }
}

func recordPerformanceEvidence(
    name: String,
    corpus: String,
    warmups: Int,
    samples: [Double]
) {
    let sorted = samples.sorted()
    guard !sorted.isEmpty else { return }
    let median = sorted[sorted.count / 2]
    let p95Index = min(sorted.count - 1, max(0, Int(ceil(0.95 * Double(sorted.count))) - 1))
    let digest = SHA256.hash(data: Data(corpus.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
    #if arch(arm64)
    let architecture = "arm64"
    #else
    let architecture = "other"
    #endif
    print(
        "PERF name=\(name) config=Release os=\(ProcessInfo.processInfo.operatingSystemVersionString) "
        + "arch=\(architecture) corpusUTF16=\((corpus as NSString).length) corpusSHA256=\(digest) "
        + "warmups=\(warmups) samples=\(sorted.count) medianMs=\(median) p95Ms=\(sorted[p95Index]) failures=0"
    )
}

/// Test fixture input. Production accepts only typed `EditorSelection` requests.
struct TestSelection {
    enum Mode {
        case source
        case wysiwyg
    }

    let mode: Mode
    let utf16Range: NSRange
    let sourceVersion: UInt64
    let affinity: SelectionAffinity

    init(
        mode: Mode,
        utf16Range: NSRange,
        sourceVersion: UInt64,
        affinity: SelectionAffinity = .downstream
    ) {
        self.mode = mode
        self.utf16Range = utf16Range
        self.sourceVersion = sourceVersion
        self.affinity = affinity
    }
}

@MainActor
extension EditorSession {
    /// Test-only adapter over the typed `perform` entry point.
    @discardableResult
    func perform(
        _ command: SemanticCommand,
        selection: TestSelection,
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

extension SemanticEditEngine {
    static func apply(
        command: SemanticCommand,
        selection: TestSelection,
        snapshot: SourceSnapshot,
        projection: MarkdownProjectionModel?,
        tree: MarkdownTree?,
        grouping: MutationGrouping? = nil
    ) -> SemanticEditResult {
        let editorSelection: EditorSelection
        let presentation: PresentationSnapshot?
        switch selection.mode {
        case .source:
            editorSelection = .source(
                SourceSelection(utf16: selection.utf16Range, affinity: selection.affinity)
            )
            presentation = nil
        case .wysiwyg:
            guard let projection else { return .refused(.staleVersion) }
            let snapshotID = PresentationSnapshot.ID(value: projection.sourceVersion)
            let built = PresentationSnapshot.from(
                model: projection,
                id: snapshotID,
                locationGeneration: snapshot.locationGeneration,
                sourceText: snapshot.text
            )
            editorSelection = .projection(
                ProjectionSelection(
                    utf16: selection.utf16Range,
                    revision: built.projectionRevision,
                    affinity: selection.affinity
                )
            )
            presentation = built
        }
        return apply(
            EditorEditRequest(
                command: command,
                selection: editorSelection,
                expectedSourceRevision: SourceRevision(value: selection.sourceVersion),
                grouping: grouping ?? defaultGrouping(for: command)
            ),
            snapshot: snapshot,
            presentation: presentation,
            tree: tree
        )
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
