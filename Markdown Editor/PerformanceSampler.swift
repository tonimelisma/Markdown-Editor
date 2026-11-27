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
        /// REQ-045: main-actor application of lexical source styling, excluding off-main tokenisation.
        case sourceHighlightApplication
        /// REQ-045: off-main incremental lexical computation, excluding attribute application.
        case sourceHighlightCompute
        /// The complete main-actor cost of one semantic formatting command.
        ///
        /// // Measured across the whole command path in `EditorSession`, not around
        /// // `EditorSemanticWorker.sync`, because the user waits for the whole path and only
        /// // part of it is the worker. The work executes off-main; the main actor blocks on it,
        /// // which is why "parsing is off-main" was never the property worth asserting.
        case semanticCommand
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
        // Off-main, in the parse task, like parsing: no frame waits on it (DECISIONS, 2026-11-27).
        .imageResolution: 100_000_000,
        .authoritativeApplication: 100_000_000,
        // A frame-shaped budget rather than the off-main 100 ms allowance: this runs on the
        // main actor and the user sees it.
        .layoutApplication: 16_000_000,
        .mainActorLatency: 16_000_000,
        .sourceHighlightApplication: 8_000_000,
        .sourceHighlightCompute: 100_000_000,
        // A frame, for the same reason as `layoutApplication`: main-actor work the user waits on.
        .semanticCommand: 16_000_000,
    ]
    struct Summary: Equatable { let metric: Metric; let count: Int; let p50: UInt64; let p95: UInt64; let max: UInt64 }

    /// One metric's samples since the last summary: every sample's count and the largest exactly,
    /// and a uniform reservoir of at most `capacity` of them for the percentiles.
    ///
    /// The reservoir replaced a ring that kept only the newest 512. The latency probe takes 600
    /// samples a minute, so each minute's summary silently lost its first nine seconds: a print
    /// panel's first load there left no trace in the count, the p95 or the max (probe
    /// 46005844047). Memory and per-record work stay bounded, as COR-30 required of the ring.
    fileprivate nonisolated struct Window {
        var count = 0
        var max: UInt64 = 0
        var reservoir: [UInt64] = []
    }

    static let capacity = 512
    private var windows: [Metric: Window] = [:]
    private var random = SplitMix64(seed: 0x9E37_79B9_7F4A_7C15)
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
        // COR-30: constant work per record, never a copy of the buffer: this runs on the
        // keystroke path, inside the very boundary the 8 ms budget measures.
        windows[metric, default: Window()].add(durationNanos, capacity: Self.capacity, random: &random)
    }

    func attach(frameObserver: FrameObserver) {
        self.frameObserver = frameObserver
    }

    func drainSummaries() -> [Summary] {
        defer { windows.removeAll() }
        return Metric.allCases.compactMap { metric in
            guard let window = windows[metric], window.count > 0 else { return nil }
            let values = window.reservoir.sorted()
            let percentile: (Double) -> UInt64 = { p in values[min(values.count - 1, max(0, Int(ceil(Double(values.count) * p)) - 1))] }
            return Summary(metric: metric, count: window.count, p50: percentile(0.5), p95: percentile(0.95), max: window.max)
        }
    }

    func flush() {
        for summary in drainSummaries() {
            trace?.record(route: .performanceSummary, .performanceSummary(metric: summary.metric, count: summary.count, p50Nanos: summary.p50, p95Nanos: summary.p95, maxNanos: summary.max))
            guard let budget = Self.budgetNanos[summary.metric] else { continue }
            if summary.p95 > budget { trace?.record(route: .budgetExceeded, .budgetExceeded(metric: summary.metric, p95Nanos: summary.p95, budgetNanos: budget)) }
        }
        if let statistics = frameObserver?.drainStatistics() {
            trace?.record(route: .frameStatistics, .frameStatistics(
                hitchMillisPerSecond: statistics.hitchMillisPerSecond,
                longestFrameNanos: statistics.longestFrameNanos,
                framesObserved: statistics.framesObserved
            ))
        }
        let memory = MemoryFootprint.sample()
        trace?.record(route: .memoryFootprint, .memoryFootprint(bytes: memory.bytes, peakBytes: memory.peakBytes))
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

fileprivate extension PerformanceSampler.Window {
    /// Algorithm R: once the reservoir is full, the n-th sample replaces a random slot with
    /// probability capacity / n, so every sample of the window is kept with the same probability.
    mutating func add(_ value: UInt64, capacity: Int, random: inout SplitMix64) {
        count += 1
        if value > max { max = value }
        if reservoir.count < capacity {
            reservoir.append(value)
        } else {
            let slot = Int(random.next() % UInt64(count))
            if slot < capacity { reservoir[slot] = value }
        }
    }
}

/// A small, fast, seeded generator: the reservoir needs uniform choices, not secrecy, and a fixed
/// seed makes a summary reproducible from the same samples.
nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
