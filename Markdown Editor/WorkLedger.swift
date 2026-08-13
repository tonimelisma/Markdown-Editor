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
    private final class Frame: @unchecked Sendable {
        let scope: WorkScope
        let parent: Frame?
        private let ledger = Mutex(WorkLedger())

        init(scope: WorkScope, parent: Frame?) {
            self.scope = scope
            self.parent = parent
        }

        func add(_ mutate: (inout WorkLedger) -> Void) {
            ledger.withLock { mutate(&$0) }
        }

        func snapshot() -> WorkLedger {
            ledger.withLock { $0 }
        }
    }

    @TaskLocal private static var currentFrame: Frame?

    static func scope<T>(
        _ scope: WorkScope,
        _ body: () throws -> T
    ) rethrows -> T {
        let frame = Frame(scope: scope, parent: currentFrame)
        return try $currentFrame.withValue(frame) {
            defer { finish(frame) }
            return try body()
        }
    }

    static func scope<T>(
        _ scope: WorkScope,
        _ body: () async throws -> T
    ) async rethrows -> T {
        let frame = Frame(scope: scope, parent: currentFrame)
        return try await $currentFrame.withValue(frame) {
            defer { finish(frame) }
            return try await body()
        }
    }

    static func add(_ mutate: (inout WorkLedger) -> Void) {
        currentFrame?.add(mutate)
    }

    static func currentForTesting() -> WorkLedger? {
        currentFrame?.snapshot()
    }

    // Test helper to clear state between tests.
    static func resetForTesting() {
        // Task-local state is scoped to the calling task and cannot leak between tests.
    }

    private static func finish(_ frame: Frame) {
        let finished = frame.snapshot()
        frame.parent?.add { $0 = $0 + finished }
        recordWorkLedger(scope: frame.scope, ledger: finished)
    }

    private static func recordWorkLedger(
        scope: WorkScope,
        ledger: WorkLedger
    ) {
        // Write through the shared serialized log so detached work cannot cross an actor-isolated
        // editor sink. The mapped event remains the same closed diagnostic vocabulary.
        Task { @MainActor in
            guard let log = DiagnosticLog.shared else { return }
            log.record(
                .workLedger,
                level: .debug,
                category: .diagnostics,
                origin: .productionRoute,
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
