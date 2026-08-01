//
//  LatestParseScheduler.swift
//  Markdown Editor
//

import Foundation

nonisolated struct LatestParseRequest: Sendable, Equatable {
    let source: SourceSnapshot
    let operationGeneration: UInt64
}

/// Demand gate for semantic work: one request may run and only the newest waiting request survives.
///
/// // REQ-111; ARC-022/ARC-Q18: this gate is an optimization boundary; EditorSession identity
/// checks remain the authority for applying a result.
@MainActor
final class LatestParseScheduler {
    private var running: LatestParseRequest?
    private var pending: LatestParseRequest?
    private(set) var requestedCount = 0
    private(set) var discardedBeforeParseCount = 0

    @discardableResult
    func submit(_ request: LatestParseRequest) -> Bool {
        requestedCount += 1
        guard running == nil else {
            if pending != nil { discardedBeforeParseCount += 1 }
            pending = request
            return false
        }
        running = request
        return true
    }

    /// Completion is keyed to the request that started it. A detached lifetime's late task must
    /// never clear the running slot belonging to a reattached lifetime.
    func finish(_ request: LatestParseRequest) -> Bool {
        guard running == request else { return false }
        running = nil
        let hasPending = pending != nil
        pending = nil
        return hasPending
    }

    func cancel() {
        running = nil
        pending = nil
    }

    var hasRunningRequest: Bool { running != nil }
    var hasPendingRequest: Bool { pending != nil }
    var pendingRequest: LatestParseRequest? { pending }
}
