import CoreVideo
import Foundation

/// Immutable sample captured by the display-link callback before it crosses to the main actor.
nonisolated struct FrameClockTick: Sendable, Equatable {
    let callbackUptimeNanos: UInt64
    let cadenceNanos: UInt64
}

/// A source of display cadence samples. The callback is never required to run on the main actor.
nonisolated protocol FrameClock: AnyObject, Sendable {
    @discardableResult
    func start(_ callback: @escaping @Sendable (FrameClockTick) -> Void) -> Bool
    func stop()
}

/// Real macOS display-link source. Only the callback box crosses Core Video's opaque pointer.
nonisolated final class DisplayLinkFrameClock: FrameClock, @unchecked Sendable {
    private final class CallbackBox: @unchecked Sendable {
        let callback: @Sendable (FrameClockTick) -> Void
        init(callback: @escaping @Sendable (FrameClockTick) -> Void) { self.callback = callback }
    }

    private var displayLink: CVDisplayLink?
    private var callbackBox: CallbackBox?

    @discardableResult
    func start(_ callback: @escaping @Sendable (FrameClockTick) -> Void) -> Bool {
        guard displayLink == nil else { return false }
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess, let link else {
            return false
        }
        let box = CallbackBox(callback: callback)
        callbackBox = box
        let pointer = Unmanaged.passUnretained(box).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { _, _, outputTime, _, _, context in
            guard let context else { return kCVReturnError }
            let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            let cadence: UInt64
            if outputTime.pointee.videoTimeScale > 0 {
                cadence = UInt64(outputTime.pointee.videoRefreshPeriod) * 1_000_000_000
                    / UInt64(outputTime.pointee.videoTimeScale)
            } else {
                cadence = 16_666_667
            }
            box.callback(FrameClockTick(
                callbackUptimeNanos: DispatchTime.now().uptimeNanoseconds,
                cadenceNanos: max(1, cadence)
            ))
            return kCVReturnSuccess
        }, pointer)
        guard CVDisplayLinkStart(link) == kCVReturnSuccess else {
            callbackBox = nil
            return false
        }
        displayLink = link
        return true
    }

    func stop() {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
        }
        callbackBox = nil
    }
}

/// Deterministic component-test clock. It uses the same callback/acknowledgement boundary as the
/// production clock, while letting tests enumerate normal, dropped, queued, and stalled frames.
nonisolated final class ControlledFrameClock: FrameClock, @unchecked Sendable {
    private var callback: (@Sendable (FrameClockTick) -> Void)?
    private(set) var isRunning = false

    @discardableResult
    func start(_ callback: @escaping @Sendable (FrameClockTick) -> Void) -> Bool {
        self.callback = callback
        isRunning = true
        return true
    }

    func stop() {
        isRunning = false
        callback = nil
    }

    func emit(callbackUptimeNanos: UInt64, cadenceNanos: UInt64) {
        guard isRunning else { return }
        callback?(FrameClockTick(
            callbackUptimeNanos: callbackUptimeNanos,
            cadenceNanos: max(1, cadenceNanos)
        ))
    }
}

/// Main-actor acknowledgement boundary kept separate from the off-main clock source.
@MainActor
final class MainActorClock {
    private let source: any FrameClock
    private var generation: UInt64 = 0

    init(source: any FrameClock) {
        self.source = source
    }

    @discardableResult
    func start(_ acknowledge: @escaping @MainActor @Sendable (FrameClockTick) -> Void) -> Bool {
        generation &+= 1
        let generation = self.generation
        let started = source.start { [weak self] tick in
            Task { @MainActor [weak self] in
                guard self?.generation == generation else { return }
                acknowledge(tick)
            }
        }
        if !started { self.generation &-= 1 }
        return started
    }

    func stop() {
        generation &+= 1
        source.stop()
    }
}

/// Observes display-link callback cadence and main-actor acknowledgement delay.
///
/// A callback timestamp is captured off-main; the acknowledgement timestamp is captured only
/// when the main actor processes that sample. This makes a blocked main actor visible instead of
/// reconstructing a smooth timeline from display-link timestamps alone.
/// // REQ-125; ARC-Q05.
@MainActor
final class FrameObserver {
    struct Statistics: Sendable, Equatable {
        let hitchMillisPerSecond: Double
        let longestFrameNanos: UInt64
        let framesObserved: Int
    }

    private let clock: MainActorClock
    private var clockRunning = false
    private var firstCallbackUptime: UInt64?
    private var lastCallbackUptime: UInt64?
    private var hitchMillis: Double = 0
    private var longestFrameNanos: UInt64 = 0
    private var framesObserved: Int = 0
    private var hitchInProgress = false
    private let sampler: PerformanceSampler

    init(sampler: PerformanceSampler, clock: any FrameClock = DisplayLinkFrameClock()) {
        self.sampler = sampler
        self.clock = MainActorClock(source: clock)
        sampler.attach(frameObserver: self)
    }

    func start() {
        guard ProcessInfo.processInfo.environment["MARKDOWN_EDITOR_FRAME_OBSERVER"] == "1",
              !clockRunning else { return }
        startClock()
    }

    func startControlled() {
        guard !clockRunning else { return }
        startClock()
    }

    private func startClock() {
        clockRunning = clock.start { [weak self] tick in self?.acknowledge(tick) }
    }

    func stop() {
        clock.stop()
        clockRunning = false
    }

    /// Deterministic seam for the complete callback-arrival → main-actor-ack path.
    func recordForTesting(callbackUptimeNanos: UInt64, ackUptimeNanos: UInt64, cadenceNanos: UInt64) {
        acknowledge(
            FrameClockTick(callbackUptimeNanos: callbackUptimeNanos, cadenceNanos: cadenceNanos),
            ackUptimeNanos: ackUptimeNanos
        )
    }

    func drainStatistics() -> Statistics? {
        guard framesObserved > 0,
              let first = firstCallbackUptime,
              let last = lastCallbackUptime else { return nil }
        let elapsed = max(
            1_000_000,
            last &- first
        )
        let result = Statistics(
            hitchMillisPerSecond: hitchMillis / (Double(elapsed) / 1_000_000_000),
            longestFrameNanos: longestFrameNanos,
            framesObserved: framesObserved
        )
        firstCallbackUptime = nil
        lastCallbackUptime = nil
        hitchMillis = 0
        longestFrameNanos = 0
        framesObserved = 0
        hitchInProgress = false
        return result
    }

    private func acknowledge(_ tick: FrameClockTick, ackUptimeNanos: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        guard tick.callbackUptimeNanos >= (lastCallbackUptime ?? tick.callbackUptimeNanos) else {
            return
        }
        guard let lastCallbackUptime else {
            firstCallbackUptime = tick.callbackUptimeNanos
            self.lastCallbackUptime = tick.callbackUptimeNanos
            return
        }
        let callbackInterval = tick.callbackUptimeNanos &- lastCallbackUptime
        let acknowledgementDelay = ackUptimeNanos >= tick.callbackUptimeNanos
            ? ackUptimeNanos &- tick.callbackUptimeNanos
            : 0
        let effectiveFrame = max(callbackInterval, acknowledgementDelay)
        let cadence = max(1, tick.cadenceNanos)
        framesObserved += 1
        longestFrameNanos = max(longestFrameNanos, effectiveFrame)
        if effectiveFrame > cadence {
            // Several callbacks can queue behind one main-actor stall. Count that contiguous
            // backlog once, while retaining the longest observed frame as the measurement.
            if !hitchInProgress {
                hitchMillis += Double(effectiveFrame - cadence) / 1_000_000
            }
            hitchInProgress = true
        } else {
            hitchInProgress = false
        }
        self.lastCallbackUptime = tick.callbackUptimeNanos
    }

}
