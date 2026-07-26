//
//  EditorSemanticWorker.swift
//  Markdown Editor
//

import Foundation

private nonisolated final class SemanticWorkerResultBox<Value: Sendable>: @unchecked Sendable {
    var value: Value?
}

/// Executes parser, source-index, and projection work away from the main actor.
///
/// Discrete semantic commands may wait for an exact answer. Ordinary input never uses this
/// synchronous boundary; it advances through local presentation transitions.
/// // REQ-085; ARC-Q06
nonisolated enum EditorSemanticWorker {
    private static let queue = DispatchQueue(
        label: "net.tonimelisma.Markdown-Editor.semantic-worker",
        qos: .userInitiated
    )

    static func sync<Value: Sendable>(
        _ work: @escaping @Sendable () -> Value
    ) -> Value {
        let completion = DispatchSemaphore(value: 0)
        let box = SemanticWorkerResultBox<Value>()
        queue.async {
            precondition(!Thread.isMainThread)
            box.value = work()
            completion.signal()
        }
        completion.wait()
        guard let value = box.value else {
            preconditionFailure("Semantic worker completed without producing a value")
        }
        return value
    }
}
