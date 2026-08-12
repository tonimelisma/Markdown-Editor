import Foundation

/// REQ-103: bounded aggregate-only timing evidence. Individual timings are never emitted.
@MainActor
final class PerformanceSampler {
    enum Metric: Sendable, CaseIterable, Hashable {
        case nativeInputCallback
        case modeTransition
        case parseProjection
        case imageResolution
        case authoritativeApplication
        /// REQ-116: TextKit layout for an applied WYSIWYG change.
        ///
        /// // The `nativeInputCallback` boundary ends when the input delegate returns — after
        /// // `storage.endEditing()` but *before* TextKit generates glyphs, lays out, or draws.
        /// // On the TextKit 1 compatibility path with `NSTextTable` and image attachments, that
        /// // layout is the most likely source of perceived jank, and every other metric measures
        /// // a phase the app owns rather than one TextKit owns.
        case layoutApplication
        /// REQ-124: main-actor hop latency, distinct from the one-second hang watchdog.
        case mainActorLatency
        case sourceHighlightApplication
    }

    /// p95 budget per metric, in nanoseconds.
    ///
    /// // REQ-090/116; ARC-Q05: one exported table, so a test can assert it agrees with the
    /// // numbers REQUIREMENTS states. These values previously existed twice — as prose in
    /// // REQ-090 and as literals inside `flush()` — with nothing tying them together.
    static let budgetNanos: [Metric: UInt64] = [
        .nativeInputCallback: 8_000_000,
        .modeTransition: 16_000_000,
        .parseProjection: 100_000_000,
        .imageResolution: 16_000_000,
        .authoritativeApplication: 100_000_000,
        // A frame-shaped budget rather than the off-main 100 ms allowance: this runs on the
        // main actor and the user sees it.
        .layoutApplication: 16_000_000,
        .mainActorLatency: 16_000_000,
        .sourceHighlightApplication: 8_000_000,
    ]
    struct Summary: Equatable { let metric: Metric; let count: Int; let p50: UInt64; let p95: UInt64; let max: UInt64 }

    private let capacity = 512
    private var samples: [Metric: [UInt64]] = [:]
    /// Next slot to overwrite once a metric's buffer is full (COR-30).
    private var writeCursor: [Metric: Int] = [:]
    private let trace: (any EditorTraceSink)?
    private weak var frameObserver: FrameObserver?
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
        // COR-30: a ring rather than `Array.removeFirst`, which copied the remaining 511 samples
        // on every record once full — O(n) work on the keystroke path, inside the very boundary
        // the 8 ms budget measures.
        var values = samples[metric, default: []]
        if values.count < capacity {
            values.append(durationNanos)
        } else {
            let cursor = writeCursor[metric, default: 0]
            values[cursor] = durationNanos
            writeCursor[metric] = (cursor + 1) % capacity
        }
        samples[metric] = values
    }

    func attach(frameObserver: FrameObserver) {
        self.frameObserver = frameObserver
    }

    func drainSummaries() -> [Summary] {
        defer { samples.removeAll(); writeCursor.removeAll() }
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
            guard let budget = Self.budgetNanos[summary.metric] else { continue }
            if summary.p95 > budget { trace?.record(.budgetExceeded(metric: summary.metric, p95Nanos: summary.p95, budgetNanos: budget)) }
        }
        if let statistics = frameObserver?.drainStatistics() {
            trace?.record(.frameStatistics(
                hitchMillisPerSecond: statistics.hitchMillisPerSecond,
                longestFrameNanos: statistics.longestFrameNanos,
                framesObserved: statistics.framesObserved
            ))
        }
        let memory = MemoryFootprint.sample()
        trace?.record(.memoryFootprint(bytes: memory.bytes, peakBytes: memory.peakBytes))
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
