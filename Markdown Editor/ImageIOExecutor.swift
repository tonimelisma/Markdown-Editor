//
//  ImageIOExecutor.swift
//  Markdown Editor
//

import Foundation

// REQ-077: dedicated non-main queue for all blocking image/filesystem work.

nonisolated final class ImageIOExecutor: @unchecked Sendable {
    static let shared = ImageIOExecutor()

    private let queue: OperationQueue
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let queueToken: UInt8 = 1

    var underlyingQueue: OperationQueue { queue }

    init(name: String = "net.melisma.MarkdownEditor.ImageIO", maxConcurrent: Int = 1) {
        let q = OperationQueue()
        q.name = name
        q.maxConcurrentOperationCount = maxConcurrent
        q.qualityOfService = .userInitiated
        let specific = DispatchQueue(label: name + ".specific")
        specific.setSpecific(key: queueKey, value: 1)
        q.underlyingQueue = specific
        self.queue = q
        _ = queueToken
    }

    /// True only when executing on this executor's underlying queue.
    var isOnExecutorQueue: Bool {
        DispatchQueue.getSpecific(key: queueKey) != nil
    }

    func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.addOperation {
                do {
                    cont.resume(returning: try work())
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { cont in
            queue.addOperation {
                cont.resume(returning: work())
            }
        }
    }
}
