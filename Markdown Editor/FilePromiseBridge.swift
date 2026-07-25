//
//  FilePromiseBridge.swift
//  Markdown Editor
//

import AppKit
import Foundation

// REQ-060/063/077: one-to-many promise receipt with exact callback accounting.

nonisolated struct FilePromiseReceiptResult: Sendable {
    let urls: [URL]
    let stagingDirectory: URL
}

nonisolated enum FilePromiseCollectorError: Error, Equatable, Sendable {
    case mismatch
    case providerError
    case timedOut
    case alreadyCompleted
}

/// Separately unit-tested accumulator for one-to-many promise reader callbacks.
nonisolated final class FilePromiseCallbackCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let expectedCount: Int
    private var received: [(URL?, Error?)] = []
    private var continuation: CheckedContinuation<[URL], Error>?
    private var completed = false

    init(expectedCount: Int) {
        self.expectedCount = expectedCount
    }

    func note(url: URL?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        received.append((url, error))
        if received.count >= expectedCount {
            finishLocked()
        }
    }

    func wait() async throws -> [URL] {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            if completed {
                lock.unlock()
                cont.resume(throwing: FilePromiseCollectorError.alreadyCompleted)
                return
            }
            if received.count >= expectedCount {
                continuation = cont
                finishLocked()
                lock.unlock()
                return
            }
            continuation = cont
            lock.unlock()
        }
    }

    func failForTimeout() {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        completed = true
        let c = continuation
        continuation = nil
        c?.resume(throwing: FilePromiseCollectorError.timedOut)
    }

    /// Drain late callbacks after terminal failure without resuming again.
    func drainLate(url: URL?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        received.append((url, error))
    }

    var isComplete: Bool {
        lock.lock(); defer { lock.unlock() }
        return completed
    }

    var receivedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return received.count
    }

    private func finishLocked() {
        guard !completed else { return }
        completed = true
        let c = continuation
        continuation = nil
        if received.contains(where: { $0.1 != nil }) {
            c?.resume(throwing: FilePromiseCollectorError.providerError)
            return
        }
        let urls = received.compactMap { $0.0 }
        if urls.count != expectedCount {
            c?.resume(throwing: FilePromiseCollectorError.mismatch)
            return
        }
        c?.resume(returning: urls)
    }
}

enum FilePromiseBridge {
    @MainActor
    static var readableDraggedTypes: [NSPasteboard.PasteboardType] {
        NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    /// Receipt deadline for expected callbacks; grace timeout after failure before staging delete.
    nonisolated static let receiptDeadline: Duration = .seconds(60)
    nonisolated static let graceTimeout: Duration = .seconds(30)

    @MainActor
    static func receive(
        _ receivers: [NSFilePromiseReceiver],
        operationQueue: OperationQueue,
        receiptDeadline: Duration = FilePromiseBridge.receiptDeadline,
        graceTimeout: Duration = FilePromiseBridge.graceTimeout
    ) async throws -> FilePromiseReceiptResult {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-editor-promise-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: staging,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var orderedURLs: [URL] = []
        var collectors: [FilePromiseCallbackCollector] = []

        do {
            for receiver in receivers {
                // Invoke once; fileNames is populated after this call.
                let collectorBox = CollectorBox()
                receiver.receivePromisedFiles(
                    atDestination: staging,
                    options: [:],
                    operationQueue: operationQueue
                ) { url, error in
                    collectorBox.forward(url: url, error: error)
                }
                let expected = max(receiver.fileNames.count, 1)
                let collector = FilePromiseCallbackCollector(expectedCount: expected)
                collectorBox.attach(collector)
                collectors.append(collector)

                let urls: [URL]
                do {
                    urls = try await withDeadline(receiptDeadline) {
                        try await collector.wait()
                    }
                } catch {
                    // Fail once; keep draining until expected or grace, then clean staging.
                    for c in collectors where !c.isComplete {
                        c.failForTimeout()
                    }
                    await drainGrace(collectors: collectors, expectedTotal: collectors.reduce(0) { _, c in
                        max(c.receivedCount, 0)
                    }, grace: graceTimeout)
                    try? FileManager.default.removeItem(at: staging)
                    if error is CancellationError || error as? FilePromiseCollectorError == .timedOut {
                        throw ImagePlacementError.promiseTimedOut
                    }
                    throw ImagePlacementError.promiseFailed
                }
                orderedURLs.append(contentsOf: urls)
            }
            return FilePromiseReceiptResult(urls: orderedURLs, stagingDirectory: staging)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private static func withDeadline<T: Sendable>(
        _ deadline: Duration,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: deadline)
                throw FilePromiseCollectorError.timedOut
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func drainGrace(
        collectors: [FilePromiseCallbackCollector],
        expectedTotal: Int,
        grace: Duration
    ) async {
        let deadline = ContinuousClock.now + grace
        while ContinuousClock.now < deadline {
            let total = collectors.reduce(0) { $0 + $1.receivedCount }
            if total >= expectedTotal { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

/// Thread-safe late binding of collector so the reader block can fire before we finish setup.
private final class CollectorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var collector: FilePromiseCallbackCollector?
    private var pending: [(URL?, Error?)] = []

    func attach(_ collector: FilePromiseCallbackCollector) {
        lock.lock()
        self.collector = collector
        let pending = self.pending
        self.pending = []
        lock.unlock()
        for (url, error) in pending {
            collector.note(url: url, error: error)
        }
    }

    func forward(url: URL?, error: Error?) {
        lock.lock()
        if let collector {
            lock.unlock()
            collector.note(url: url, error: error)
        } else {
            pending.append((url, error))
            lock.unlock()
        }
    }
}
