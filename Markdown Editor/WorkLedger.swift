import Foundation
import Synchronization

/// Stable identity for one user-invoked operation and all of its downstream work.
///
/// The raw value is intentionally opaque and is only emitted as a numeric diagnostic field.
/// // REQ-123; ARC-026.
nonisolated struct IntentID: RawRepresentable, Hashable, Sendable, Equatable {
    let rawValue: UInt64
}

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

/// Explicit, sendable context retained by every downstream operation.
nonisolated struct IntentContext: Sendable, Equatable {
    let id: IntentID
    let scope: WorkScope
    let recorder: IntentRecorder

    static func == (lhs: IntentContext, rhs: IntentContext) -> Bool {
        lhs.id == rhs.id && lhs.scope == rhs.scope
    }
}

/// Lock-guarded, session-owned recorder. It has no task-local or process-global current owner:
/// callers must pass the context through every actor, task, and GCD boundary.
nonisolated final class IntentRecorder: @unchecked Sendable {
    private struct State {
        var nextID: UInt64 = 0
        var ledgers: [IntentID: WorkLedger] = [:]
    }

    private let state = Mutex(State())

    func begin(_ scope: WorkScope) -> IntentContext {
        state.withLock { state in
            state.nextID &+= 1
            let id = IntentID(rawValue: state.nextID)
            state.ledgers[id] = WorkLedger()
            return IntentContext(id: id, scope: scope, recorder: self)
        }
    }

    func add(_ context: IntentContext, _ mutate: (inout WorkLedger) -> Void) {
        state.withLock { state in
            guard state.ledgers[context.id] != nil else { return }
            mutate(&state.ledgers[context.id]!)
        }
    }

    func snapshot(_ context: IntentContext) -> WorkLedger? {
        state.withLock { $0.ledgers[context.id] }
    }

    /// Completes an intent exactly once. A late/cancelled operation is terminally classified as
    /// an orphan instead of silently losing the work it performed.
    @discardableResult
    func finish(_ context: IntentContext, orphaned: Bool = false) -> Bool {
        let ledger: WorkLedger? = state.withLock { $0.ledgers.removeValue(forKey: context.id) }
        guard let ledger else { return false }
        recordWorkLedger(context: context, ledger: ledger, orphaned: orphaned)
        return true
    }

    private func recordWorkLedger(context: IntentContext, ledger: WorkLedger, orphaned: Bool) {
        Task { @MainActor in
            guard let log = DiagnosticLog.shared else { return }
            log.recordProduction(
                .workLedger,
                level: orphaned ? .fault : .debug,
                category: .diagnostics,
                route: .workLedger,
                data: [
                    (.scope, .symbol(context.scope.symbol)),
                    (.intentID, .uint(context.id.rawValue)),
                    (.orphaned, .bool(orphaned)),
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
