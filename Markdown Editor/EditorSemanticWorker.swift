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
    private static let queueKey = DispatchSpecificKey<UInt8>()
    private static let queue: DispatchQueue = {
        let queue = DispatchQueue(
            label: "net.tonimelisma.Markdown-Editor.semantic-worker",
            qos: .userInitiated
        )
        queue.setSpecific(key: queueKey, value: 1)
        return queue
    }()

    static func sync<Value: Sendable>(
        intent: IntentContext? = nil,
        _ work: @escaping @Sendable () -> Value
    ) -> Value {
        // Semantic planner gates may share this boundary while already executing on the worker.
        // Re-enqueueing onto this serial queue would wait for itself forever and leave the test
        // process without a result bundle. Nested work is already off-main, so execute it
        // directly while retaining the outer intent's worker ownership.
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return work()
        }
        let isMain = Thread.isMainThread
        let t0 = isMain ? DispatchTime.now().uptimeNanoseconds : 0
        let completion = DispatchSemaphore(value: 0)
        let box = SemanticWorkerResultBox<Value>()
        queue.async {
            precondition(!Thread.isMainThread)
            box.value = work()
            completion.signal()
        }
        completion.wait()
        if isMain {
            let dt = DispatchTime.now().uptimeNanoseconds &- t0
            if let intent {
                intent.recorder.add(intent) { $0.mainThreadBlockedNanos &+= dt }
            }
        }
        guard let value = box.value else {
            preconditionFailure("Semantic worker completed without producing a value")
        }
        return value
    }
}
