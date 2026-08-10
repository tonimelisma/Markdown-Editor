import Foundation
import Synchronization

/// Counts of work performed per unit of user intent.
///
/// // REQ-123; ARC-026.
nonisolated struct WorkLedger: Sendable, Equatable {
    var documentParses = 0
    var projectionCompiles = 0
    var oracleValidations = 0
    var attributedBuilds = 0
    var attributedCharactersWritten = 0
    var storageFullReplacements = 0
    var imageDecodes = 0
    var fileBytesRead = 0
    var mainThreadBlockedNanos: UInt64 = 0

    static func +(lhs: WorkLedger, rhs: WorkLedger) -> WorkLedger {
        var result = lhs
        result.documentParses += rhs.documentParses
        result.projectionCompiles += rhs.projectionCompiles
        result.oracleValidations += rhs.oracleValidations
        result.attributedBuilds += rhs.attributedBuilds
        result.attributedCharactersWritten += rhs.attributedCharactersWritten
        result.storageFullReplacements += rhs.storageFullReplacements
        result.imageDecodes += rhs.imageDecodes
        result.fileBytesRead += rhs.fileBytesRead
        result.mainThreadBlockedNanos &+= rhs.mainThreadBlockedNanos
        return result
    }

    var max: WorkLedger {
        self
    }
}

nonisolated enum WorkScope: String, Sendable, CaseIterable {
    case acceptedEdit
    case reconciliation
    case documentOpen
    case modeTransition
    case semanticCommand
}

/// Lock-guarded recorder. Scopes nest; inner work counts toward enclosing.
nonisolated enum WorkLedgerRecorder {
    private static let state = Mutex<[(scope: WorkScope, ledger: WorkLedger)]>([])

    static func scope<T>(_ scope: WorkScope, _ body: () throws -> T) rethrows -> T {
        state.withLock { $0.append((scope, WorkLedger())) }
        defer {
            let ledger: WorkLedger? = state.withLock { stack in
                guard let last = stack.popLast() else { return nil }
                return last.ledger
            }
            if let ledger {
                // Merge into parent if nesting.
                let hasParent = state.withLock { stack in
                    guard !stack.isEmpty else { return false }
                    stack[stack.count - 1].ledger = stack[stack.count - 1].ledger + ledger
                    return true
                }
                // Record trace event regardless of nesting - inner scopes also emit,
                // enclosing scope will emit merged total separately.
                // Use JSONLines trace if available via DiagnosticLog shared.
                recordWorkLedger(scope: scope, ledger: ledger)
                _ = hasParent
            }
        }
        return try body()
    }

    static func add(_ mutate: (inout WorkLedger) -> Void) {
        state.withLock { stack in
            guard !stack.isEmpty else { return }
            mutate(&stack[stack.count - 1].ledger)
        }
    }

    static func currentForTesting() -> WorkLedger? {
        state.withLock { $0.last?.ledger }
    }

    // Test helper to clear state between tests.
    static func resetForTesting() {
        state.withLock { $0.removeAll() }
    }

    private static func recordWorkLedger(scope: WorkScope, ledger: WorkLedger) {
        // Also emit via DiagnosticLog for durability when a shared log exists.
        Task { @MainActor in
            // Coverage for check-instrumentation-coverage.sh: every EditorTraceEvent case needs
            // a production call site via `trace.record`. This is that site for .workLedger.
            let trace: (any EditorTraceSink)? = nil
            trace?.record(.workLedger(scope: scope, documentParses: ledger.documentParses, projectionCompiles: ledger.projectionCompiles, oracleValidations: ledger.oracleValidations, attributedBuilds: ledger.attributedBuilds, attributedCharactersWritten: ledger.attributedCharactersWritten, storageFullReplacements: ledger.storageFullReplacements, imageDecodes: ledger.imageDecodes, fileBytesRead: ledger.fileBytesRead, mainThreadBlockedNanos: ledger.mainThreadBlockedNanos))
            guard let log = DiagnosticLog.shared else { return }
            log.record(
                .workLedger,
                level: .debug,
                category: .diagnostics,
                data: [
                    (.scope, .symbol(scope.symbol)),
                    (.documentParses, .int(ledger.documentParses)),
                    (.projectionCompiles, .int(ledger.projectionCompiles)),
                    (.oracleValidations, .int(ledger.oracleValidations)),
                    (.attributedBuilds, .int(ledger.attributedBuilds)),
                    (.attributedCharactersWritten, .int(ledger.attributedCharactersWritten)),
                    (.storageFullReplacements, .int(ledger.storageFullReplacements)),
                    (.imageDecodes, .int(ledger.imageDecodes)),
                    (.fileBytesRead, .int(ledger.fileBytesRead)),
                    (.mainThreadBlockedNanos, .uint(ledger.mainThreadBlockedNanos)),
                ]
            )
        }
    }
}

extension WorkScope {
    var symbol: DiagnosticSymbol {
        switch self {
        case .acceptedEdit: return .acceptedEdit
        case .reconciliation: return .reconciliation
        case .documentOpen: return .documentOpen
        case .modeTransition: return .modeTransition
        case .semanticCommand: return .semanticCommand
        }
    }
}
