import Foundation

/// REQ-103: bounded aggregate-only timing evidence. Individual timings are never emitted.
@MainActor
final class PerformanceSampler {
    enum Metric: Sendable, CaseIterable { case keystrokeTranslation, modeToggle, reconciliation }
    struct Summary: Equatable { let metric: Metric; let count: Int; let p50: UInt64; let p95: UInt64; let max: UInt64 }

    private let capacity = 512
    private var samples: [Metric: [UInt64]] = [:]
    private weak var trace: (any EditorTraceSink)?
    private var timer: Timer?

    init(trace: (any EditorTraceSink)?) {
        self.trace = trace
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
        PerformanceSamplerRegistry.add(self)
    }

    func record(_ metric: Metric, durationNanos: UInt64) {
        var values = samples[metric, default: []]
        if values.count == capacity { values.removeFirst() }
        values.append(durationNanos)
        samples[metric] = values
    }

    func drainSummaries() -> [Summary] {
        defer { samples.removeAll() }
        return Metric.allCases.compactMap { metric in
            let values = samples[metric, default: []].sorted()
            guard !values.isEmpty else { return nil }
            let percentile: (Double) -> UInt64 = { p in values[min(values.count - 1, max(0, Int(ceil(Double(values.count) * p)) - 1))] }
            return Summary(metric: metric, count: values.count, p50: percentile(0.5), p95: percentile(0.95), max: values.last!)
        }
    }

    func flush() {
        for summary in drainSummaries() {
            trace?.record(.performanceSummary(metric: summary.metric, count: summary.count, p50Nanos: summary.p50, p95Nanos: summary.p95, maxNanos: summary.max))
            let budget: UInt64 = switch summary.metric { case .keystrokeTranslation: 8_000_000; case .modeToggle: 16_000_000; case .reconciliation: 100_000_000 }
            if summary.p95 > budget { trace?.record(.budgetExceeded(metric: summary.metric, p95Nanos: summary.p95, budgetNanos: budget)) }
        }
    }
}

@MainActor
private enum PerformanceSamplerRegistry {
    private static var samplers: [PerformanceSampler] = []
    static func add(_ sampler: PerformanceSampler) { samplers.append(sampler) }
    static func flushAll() { samplers.forEach { $0.flush() }; samplers.removeAll { _ in false } }
}

@MainActor
func flushPerformanceSamplingAtRunEnd() { PerformanceSamplerRegistry.flushAll() }
