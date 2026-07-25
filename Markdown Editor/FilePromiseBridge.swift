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
}

/// Separately unit-tested accumulator for one-to-many promise reader callbacks.
nonisolated final class FilePromiseCallbackCollector: @unchecked Sendable {
    private let lock = NSLock()
    let expectedCount: Int
    private var received: [(URL?, Error?)] = []
    private var continuation: CheckedContinuation<[URL], Error>?
    private var completed = false
    private var storedResult: Result<[URL], Error>?

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
            if let stored = storedResult {
                lock.unlock()
                cont.resume(with: stored)
                return
            }
            if completed {
                // Timed out / failed without a stored success result.
                lock.unlock()
                cont.resume(throwing: FilePromiseCollectorError.timedOut)
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
        storedResult = .failure(FilePromiseCollectorError.timedOut)
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
            let result: Result<[URL], Error> = .failure(FilePromiseCollectorError.providerError)
            storedResult = result
            c?.resume(with: result)
            return
        }
        let urls = received.compactMap { $0.0 }
        if urls.count != expectedCount {
            let result: Result<[URL], Error> = .failure(FilePromiseCollectorError.mismatch)
            storedResult = result
            c?.resume(with: result)
            return
        }
        let result: Result<[URL], Error> = .success(urls)
        storedResult = result
        c?.resume(with: result)
    }
}

enum FilePromiseBridge {
    @MainActor
    static var readableDraggedTypes: [NSPasteboard.PasteboardType] {
        NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    nonisolated static let receiptDeadline: Duration = .seconds(60)
    nonisolated static let graceTimeout: Duration = .seconds(30)

    /// Receive promised files. Staging create/cleanup runs on `operationQueue` (non-main).
    @MainActor
    static func receive(
        _ receivers: [NSFilePromiseReceiver],
        operationQueue: OperationQueue,
        receiptDeadline: Duration = FilePromiseBridge.receiptDeadline,
        graceTimeout: Duration = FilePromiseBridge.graceTimeout,
        executor: ImageIOExecutor = .shared
    ) async throws -> FilePromiseReceiptResult {
        let staging = try await executor.run { () -> URL in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("md-editor-promise-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            return url
        }

        var orderedURLs: [URL] = []
        var collectors: [FilePromiseCallbackCollector] = []
        var expectedTotal = 0

        do {
            for receiver in receivers {
                let collectorBox = CollectorBox()
                receiver.receivePromisedFiles(
                    atDestination: staging,
                    options: [:],
                    operationQueue: operationQueue
                ) { url, error in
                    collectorBox.forward(url: url, error: error)
                }
                let expected = max(receiver.fileNames.count, 1)
                expectedTotal += expected
                let collector = FilePromiseCallbackCollector(expectedCount: expected)
                collectorBox.attach(collector)
                collectors.append(collector)

                let urls: [URL]
                do {
                    urls = try await withDeadline(receiptDeadline) {
                        try await collector.wait()
                    }
                } catch {
                    for c in collectors where !c.isComplete {
                        c.failForTimeout()
                    }
                    await drainGrace(
                        collectors: collectors,
                        expectedTotal: expectedTotal,
                        grace: graceTimeout
                    )
                    await executor.run {
                        try? FileManager.default.removeItem(at: staging)
                    }
                    if error is CancellationError || error as? FilePromiseCollectorError == .timedOut {
                        throw ImagePlacementError.promiseTimedOut
                    }
                    throw ImagePlacementError.promiseFailed
                }
                orderedURLs.append(contentsOf: urls)
            }
            return FilePromiseReceiptResult(urls: orderedURLs, stagingDirectory: staging)
        } catch {
            await executor.run {
                try? FileManager.default.removeItem(at: staging)
            }
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
