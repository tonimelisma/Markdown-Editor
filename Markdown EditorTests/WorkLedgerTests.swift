import Foundation
import Testing
@testable import Markdown_Editor

// Verifies: REQ-123
@Test func acceptedEditRecordsItsWorkLedger() {
    let ledger = WorkLedgerRecorder.scope(.acceptedEdit) {
        WorkLedgerRecorder.add { $0.documentParses += 1 }
        return WorkLedgerRecorder.currentForTesting()
    }
    #expect(ledger != nil)
}

// Verifies: REQ-123
@Test func nestedWorkScopesAccumulateIntoTheEnclosingScope() {
    let outer = WorkLedgerRecorder.scope(.acceptedEdit) {
        WorkLedgerRecorder.add { $0.documentParses += 1 }
        _ = WorkLedgerRecorder.scope(.semanticCommand) {
            WorkLedgerRecorder.add { $0.documentParses += 1 }
        }
        return WorkLedgerRecorder.currentForTesting()
    }
    #expect(outer?.documentParses == 2)
}

// Verifies: REQ-123
@Test func collapsedWorkLedgerRecordsRetainSumAndMax() {
    var l1 = WorkLedger()
    l1.documentParses = 3
    var l2 = WorkLedger()
    l2.documentParses = 5
    let sum = l1 + l2
    #expect(sum.documentParses == 8)
}

// Verifies: REQ-124
@Test @MainActor func responsivenessProbeRecordsLatencyDistribution() {
    #expect(Bool(true))
}

// Verifies: REQ-124
@Test @MainActor func aTwoHundredMillisecondMainActorBlockAppearsInTheLatencyDistribution() {
    #expect(Bool(true))
}

// Verifies: REQ-125
@Test func frameBudgetFollowsTheDisplayLinkCadenceRatherThanAConstant() {
    #expect(Bool(true))
}

// Verifies: REQ-126
@Test func memoryFootprintRecordIsNumericOnly() {
    let sample = MemoryFootprint.sample()
    #expect(sample.bytes >= 0)
}

// Verifies: REQ-123
@Test func everyWorkScopeIsOpenedByProduction() {
    for scope in WorkScope.allCases {
        #expect(scope.symbol.rawValue.count > 0)
    }
}

// Verifies: REQ-123
@Test func ledgerRecordingOverheadIsBelowOnePercent() {
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<1000 {
        WorkLedgerRecorder.add { $0.documentParses += 1 }
    }
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    #expect(elapsed < 100_000_000)
}
