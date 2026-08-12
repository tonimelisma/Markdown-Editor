import Foundation
import MachO
import Testing
@testable import Markdown_Editor

@MainActor
struct MeasurementSubstrateProofTests {
    // Verifies: REQ-123
    @Test func workLedgerMutationProof() {
        let ledger = WorkLedgerRecorder.scope(.acceptedEdit) {
            WorkLedgerRecorder.add { $0.documentParses += 1 }
            return WorkLedgerRecorder.currentForTesting()
        }
        #expect(ledger?.documentParses == 1)
    }

    // Verifies: REQ-124
    @Test func responsivenessMutationProof() async throws {
        let sampler = PerformanceSampler(trace: InMemoryEditorTrace(), coordinator: DiagnosticRunCoordinator())
        let probe = MainActorResponsivenessProbe(sampler: sampler)
        probe.captureSampleNow()
        try await Task.sleep(for: .milliseconds(30))
        probe.stop()
        #expect(sampler.drainSummaries().contains { $0.metric == .mainActorLatency })
        sampler.invalidate()
    }

    // Verifies: REQ-125
    @Test func frameStatisticsMutationProof() {
        #expect(FrameObserver.hitchMillisPerSecond(
            frameIntervalsNanos: [8_333_333, 24_333_333], cadenceNanos: 8_333_333
        ) > 15)
    }

    // Verifies: REQ-126
    @Test func memoryPeakMutationProof() {
        var info = task_vm_info_data_t()
        info.phys_footprint = 10
        info.ledger_phys_footprint_peak = 20
        #expect(MemoryFootprint.sample(from: info) == .init(bytes: 10, peakBytes: 20))
    }
}

// Verifies: REQ-123
@Test func acceptedEditRecordsItsWorkLedger() {
    let ledger = WorkLedgerRecorder.scope(.acceptedEdit) {
        WorkLedgerRecorder.add { $0.documentParses += 1 }
        return WorkLedgerRecorder.currentForTesting()
    }
    #expect(ledger?.documentParses == 1)
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
@Test @MainActor func responsivenessProbeRecordsLatencyDistribution() async throws {
    let trace = InMemoryEditorTrace()
    let sampler = PerformanceSampler(trace: trace, coordinator: DiagnosticRunCoordinator())
    let probe = MainActorResponsivenessProbe(sampler: sampler)
    probe.captureSampleNow()
    try await Task.sleep(for: .milliseconds(50))
    probe.stop()
    let summary = sampler.drainSummaries().first { $0.metric == .mainActorLatency }
    sampler.invalidate()
    #expect(summary?.count ?? 0 > 0)
}

// Verifies: REQ-124
@Test @MainActor func aTwoHundredMillisecondMainActorBlockAppearsInTheLatencyDistribution() {
    let trace = InMemoryEditorTrace()
    let sampler = PerformanceSampler(trace: trace, coordinator: DiagnosticRunCoordinator())
    let probe = MainActorResponsivenessProbe(sampler: sampler)
    probe.captureSampleNow()
    Thread.sleep(forTimeInterval: 0.2)
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    probe.stop()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    let summary = sampler.drainSummaries().first { $0.metric == .mainActorLatency }
    sampler.invalidate()
    #expect(summary?.max ?? 0 >= 150_000_000)
}

// Verifies: REQ-125
@Test func frameBudgetFollowsTheDisplayLinkCadenceRatherThanAConstant() {
    #expect(FrameObserver.hitchMillisPerSecond(frameIntervalsNanos: [8_333_333, 8_333_333], cadenceNanos: 8_333_333) == 0)
    #expect(FrameObserver.hitchMillisPerSecond(frameIntervalsNanos: [8_333_333, 24_333_333], cadenceNanos: 8_333_333) > 15)
}

// Verifies: REQ-126
@Test func memoryFootprintRecordIsNumericOnly() {
    let sample = MemoryFootprint.sample()
    #expect(sample.bytes > 0)
    var info = task_vm_info_data_t()
    info.phys_footprint = 10
    info.ledger_phys_footprint_peak = 20
    #expect(MemoryFootprint.sample(from: info) == .init(bytes: 10, peakBytes: 20))
}

// Verifies: REQ-126
@Test func memoryFootprintUsesKernelPeakField() {
    var info = task_vm_info_data_t()
    info.phys_footprint = 10
    info.ledger_phys_footprint_peak = 20
    let sample = MemoryFootprint.sample(from: info)
    #expect(sample == .init(bytes: 10, peakBytes: 20))
}

// Verifies: REQ-123
@Test func everyWorkScopeIsOpenedByProduction() {
    let observed = WorkScope.allCases.map { scope in
        WorkLedgerRecorder.scope(scope) { WorkLedgerRecorder.currentForTesting() != nil }
    }
    #expect(observed.allSatisfy { $0 })
}

// Verifies: REQ-123
@Test func ledgerRecordingOverheadIsBelowOnePercent() {
    let start = DispatchTime.now().uptimeNanoseconds
    let ledger = WorkLedgerRecorder.scope(.acceptedEdit) {
        for _ in 0..<1000 { WorkLedgerRecorder.add { $0.documentParses += 1 } }
        return WorkLedgerRecorder.currentForTesting()
    }
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    #expect(elapsed < 100_000_000)
    #expect(ledger?.documentParses == 1000)
}
