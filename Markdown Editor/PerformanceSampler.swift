import Foundation

/// REQ-103: bounded aggregate-only timing evidence. Individual timings are never emitted.
@MainActor
final class PerformanceSampler {
    enum Metric: Sendable, CaseIterable {
        case nativeInputCallback
        case modeTransition
        case parseProjection
        case imageResolution
        case authoritativeApplication
    }
    struct Summary: Equatable { let metric: Metric; let count: Int; let p50: UInt64; let p95: UInt64; let max: UInt64 }

    private let capacity = 512
    private var samples: [Metric: [UInt64]] = [:]
    private let trace: (any EditorTraceSink)?
    private var timer: Timer?
    private let coordinator: DiagnosticRunCoordinator
    private var invalidated = false

    init(
        trace: (any EditorTraceSink)?,
        coordinator: DiagnosticRunCoordinator = .shared
    ) {
        self.trace = trace
        self.coordinator = coordinator
        coordinator.register(self)
        start()
    }

    func start() {
        guard timer == nil, !invalidated else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flush()
            }
        }
    }

    func record(_ metric: Metric, durationNanos: UInt64) {
        guard !invalidated else { return }
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
            let budget: UInt64 = switch summary.metric {
            case .nativeInputCallback: 8_000_000
            case .modeTransition: 16_000_000
            case .parseProjection, .imageResolution, .authoritativeApplication: 100_000_000
            }
            if summary.p95 > budget { trace?.record(.budgetExceeded(metric: summary.metric, p95Nanos: summary.p95, budgetNanos: budget)) }
        }
    }
    /// Stops the timer, emits the final aggregate once, and releases the run registration.
    func invalidate() {
        guard !invalidated else { return }
        timer?.invalidate()
        timer = nil
        flush()
        invalidated = true
        coordinator.unregister(self)
    }

}
