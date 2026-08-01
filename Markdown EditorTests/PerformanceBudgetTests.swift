//
//  PerformanceBudgetTests.swift
//  Markdown EditorTests
//

import Foundation
import Testing
@testable import Markdown_Editor

/// // Verifies: REQ-090/103/116; ARC-Q05/ARC-020 — every metric is budgeted, and the budgets in
/// code are the ones REQUIREMENTS states.
///
/// The thresholds previously existed twice: as prose in REQ-090 and as literals inside
/// `PerformanceSampler.flush()`, with nothing tying them together, so they could drift in either
/// direction without any gate noticing.
@MainActor
struct PerformanceBudgetTests {
    /// A new metric must not ship unbudgeted — an unbudgeted metric is reported but never
    /// compared against anything, which reads as coverage and proves nothing.
    @Test func everyMetricHasABudget() {
        for metric in PerformanceSampler.Metric.allCases {
            #expect(
                PerformanceSampler.budgetNanos[metric] != nil,
                "\(metric) has no budget in PerformanceSampler.budgetNanos"
            )
        }
        #expect(PerformanceSampler.budgetNanos.count == PerformanceSampler.Metric.allCases.count)
    }

    /// The exact numbers REQ-090 and ARC-Q05 state.
    @Test func budgetsMatchTheApprovedRequirementValues() {
        #expect(PerformanceSampler.budgetNanos[.nativeInputCallback] == 8_000_000)
        #expect(PerformanceSampler.budgetNanos[.modeTransition] == 16_000_000)
        #expect(PerformanceSampler.budgetNanos[.parseProjection] == 100_000_000)
        #expect(PerformanceSampler.budgetNanos[.imageResolution] == 100_000_000)
        #expect(PerformanceSampler.budgetNanos[.authoritativeApplication] == 100_000_000)
        // REQ-116: layout runs on the main actor and the user sees it, so it gets a frame-shaped
        // budget rather than the off-main allowance.
        #expect(PerformanceSampler.budgetNanos[.layoutApplication] == 16_000_000)
    }

    /// Every metric maps to a distinct closed symbol, so a run log can name it (ARC-016).
    @Test func everyMetricHasADistinctSymbol() {
        let symbols = PerformanceSampler.Metric.allCases.map(\.symbol)
        #expect(Set(symbols).count == symbols.count, "two metrics share a diagnostic symbol")
    }

    /// A metric over budget records `budgetExceeded`; one within budget does not.
    @Test func exceedingABudgetIsRecorded() {
        let trace = InMemoryEditorTrace()
        let sampler = PerformanceSampler(trace: trace, coordinator: DiagnosticRunCoordinator())
        let budget = PerformanceSampler.budgetNanos[.layoutApplication]!
        sampler.record(.layoutApplication, durationNanos: budget * 4)
        sampler.flush()
        #expect(!trace.eventsMatching {
            if case .budgetExceeded(let metric, _, _) = $0 { return metric == .layoutApplication }
            return false
        }.isEmpty, "an over-budget metric recorded nothing")

        let quiet = InMemoryEditorTrace()
        let second = PerformanceSampler(trace: quiet, coordinator: DiagnosticRunCoordinator())
        second.record(.layoutApplication, durationNanos: budget / 4)
        second.flush()
        #expect(quiet.eventsMatching {
            if case .budgetExceeded = $0 { return true }
            return false
        }.isEmpty, "a within-budget metric reported a breach")
        sampler.invalidate()
        second.invalidate()
    }
}
