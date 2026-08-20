//
//  TestHelpers.swift
//  Markdown EditorTests
//

import Foundation
import CryptoKit
@testable import Markdown_Editor

@MainActor
final class TestImagePicker: ImagePicking {
    let urls: [URL]
    init(_ urls: [URL]) { self.urls = urls }
    func pickImages() async -> [URL] { urls }
}

extension Result {
    func get() -> Success? {
        if case .success(let value) = self { return value }
        return nil
    }
}

@MainActor
@discardableResult
func commitSourceMutationForTest(
    _ document: MarkdownDocument,
    _ mutation: SourceMutation
) -> SourceEditResult {
    let input = EditorInput.sourceReplacement(
        EditorReplacementInput(
            mutation: mutation,
            selectionIdentity: .source(mutation.selectionBefore)
        )
    )
    let result = document.commitEditorInput(
        input,
        state: EditorStateSnapshot(
            source: document.sourceSnapshot(),
            sourceSelection: mutation.selectionBefore
        )
    )
    switch result {
    case .committed(let transaction):
        guard case .edit(let edit) = transaction.effect else {
            return .refused(.conflict)
        }
        return .committed(edit.sourceSelectionAfter)
    case .refused(let refusal):
        return .refused(refusal.asSourceRefusal)
    }
}

/// Production Swift sources, for structural gates that prove a displaced route is gone rather
/// than merely unused. Source inspection is the only available proof of an *absence*.
func productionSourceFiles() throws -> [URL] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Markdown Editor")
    return try FileManager.default
        .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

func productionSourceText() throws -> String {
    try productionSourceFiles()
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
}

struct PerformanceEvidence: Equatable, Sendable {
    let warmups: Int
    let samples: [Double]
    let median: Double?
    let p95: Double?
    let failures: [String]

    init(warmups: Int, samples: [Double], failures: [String] = []) {
        let sorted = samples.sorted()
        self.warmups = warmups
        self.samples = sorted
        self.median = sorted.isEmpty ? nil : sorted[sorted.count / 2]
        if sorted.isEmpty {
            self.p95 = nil
        } else {
            let index = min(sorted.count - 1, max(0, Int(ceil(0.95 * Double(sorted.count))) - 1))
            self.p95 = sorted[index]
        }
        self.failures = sorted.isEmpty ? failures + ["no performance samples"] : failures
    }
}

func recordPerformanceEvidence(
    name: String,
    corpus: String,
    warmups: Int,
    samples: [Double],
    failures: [String] = []
) -> PerformanceEvidence {
    let evidence = PerformanceEvidence(warmups: warmups, samples: samples, failures: failures)
    let digest = SHA256.hash(data: Data(corpus.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
    #if arch(arm64)
    let architecture = "arm64"
    #else
    let architecture = "other"
    #endif
    #if DEBUG
    let configuration = "Debug"
    #else
    let configuration = "Release"
    #endif
    let median = evidence.median.map { String($0) } ?? "nil"
    let p95 = evidence.p95.map { String($0) } ?? "nil"
    print(
        "PERF name=\(name) config=\(configuration) os=\(ProcessInfo.processInfo.operatingSystemVersionString) "
        + "arch=\(architecture) corpusUTF16=\((corpus as NSString).length) corpusSHA256=\(digest) "
        + "warmups=\(evidence.warmups) samples=\(evidence.samples.count) "
        + "medianMs=\(median) p95Ms=\(p95) failures=\(evidence.failures.count)"
    )
    return evidence
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
        captureSelection(editorSelection)
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
