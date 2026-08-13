import CoreVideo
import Foundation

/// Observes real display-link intervals and derives hitch statistics.
///
/// // REQ-125.
@MainActor
final class FrameObserver {
    struct Statistics: Sendable, Equatable {
        let hitchMillisPerSecond: Double
        let longestFrameNanos: UInt64
        let framesObserved: Int
    }

    private var displayLink: CVDisplayLink?
    private var firstTimestamp: Double?
    private var lastTimestamp: Double?
    private var hitchMillis: Double = 0
    private var longestFrameNanos: UInt64 = 0
    private var framesObserved: Int = 0
    private let sampler: PerformanceSampler

    init(sampler: PerformanceSampler) {
        self.sampler = sampler
        sampler.attach(frameObserver: self)
    }

    func start() {
        guard ProcessInfo.processInfo.environment["MARKDOWN_EDITOR_FRAME_OBSERVER"] == "1",
              displayLink == nil else { return }
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess, let link else { return }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { _, _, outputTime, _, _, context in
            guard let context else { return kCVReturnError }
            let hostTime = outputTime.pointee.hostTime
            let cadenceNanos = outputTime.pointee.videoTimeScale > 0
                ? UInt64(outputTime.pointee.videoRefreshPeriod) * 1_000_000_000
                    / UInt64(outputTime.pointee.videoTimeScale)
                : 16_666_667
            let observer = Unmanaged<FrameObserver>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak observer] in
                observer?.record(hostTime: hostTime, cadenceNanos: cadenceNanos)
            }
            return kCVReturnSuccess
        }, pointer)
        guard CVDisplayLinkStart(link) == kCVReturnSuccess else { return }
        displayLink = link
    }

    func stop() {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
        }
    }

    /// Component-test seam for the same owner callback used by CVDisplayLink. It supplies host
    /// timestamps without screen automation, so the sampler's production flush route can be
    /// observed on a machine where no display link is available.
    func recordForTesting(hostTime: UInt64, cadenceNanos: UInt64) {
        record(hostTime: hostTime, cadenceNanos: cadenceNanos)
    }

    func drainStatistics() -> Statistics? {
        guard framesObserved > 0, let first = firstTimestamp, let last = lastTimestamp else { return nil }
        let elapsed = max(0.001, last - first)
        let result = Statistics(
            hitchMillisPerSecond: hitchMillis / elapsed,
            longestFrameNanos: longestFrameNanos,
            framesObserved: framesObserved
        )
        firstTimestamp = nil
        lastTimestamp = nil
        hitchMillis = 0
        longestFrameNanos = 0
        framesObserved = 0
        return result
    }

    private func record(hostTime: UInt64, cadenceNanos: UInt64) {
        let timestamp = Double(hostTime) / CVGetHostClockFrequency()
        if let lastTimestamp {
            let interval = max(0, timestamp - lastTimestamp)
            let cadence = Double(cadenceNanos) / 1_000_000_000
            let frameNanos = UInt64(interval * 1_000_000_000)
            framesObserved += 1
            longestFrameNanos = max(longestFrameNanos, frameNanos)
            if interval > cadence { hitchMillis += (interval - cadence) * 1000 }
        } else {
            firstTimestamp = timestamp
        }
        self.lastTimestamp = timestamp
    }

    nonisolated static func hitchMillisPerSecond(
        frameIntervalsNanos: [UInt64],
        cadenceNanos: UInt64,
        observedNanos: UInt64? = nil
    ) -> Double {
        guard cadenceNanos > 0 else { return 0 }
        let excessMillis = frameIntervalsNanos.reduce(0.0) { total, interval in
            total + Double(interval > cadenceNanos ? interval - cadenceNanos : 0) / 1_000_000
        }
        let denominator = Double(observedNanos ?? max(cadenceNanos, frameIntervalsNanos.reduce(0, +))) / 1_000_000_000
        return denominator > 0 ? excessMillis / denominator : 0
    }
}
