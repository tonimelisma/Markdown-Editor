import Foundation
import Synchronization

/// Serializes all file writes, including records produced while the main actor is blocked.
final class DiagnosticWriteCoordinator: Sendable {
    private struct State {
        var tail: Task<Bool, Never>?
        var nextSequence: UInt64 = 0
        var closed = false
    }

    private let state = Mutex(State(tail: nil))
    private let sink: DiagnosticFileSink

    init(sink: DiagnosticFileSink) {
        self.sink = sink
    }

    func appendUnsequenced(_ lines: [String]) -> Task<Bool, Never>? {
        state.withLock { state in
            guard !state.closed else { return nil }
            let previous = state.tail
            let sink = self.sink
            let task = Task.detached {
                _ = await previous?.value
                return await sink.append(lines)
            }
            state.tail = task
            return task
        }
    }

    /// Allocates the sequence and reserves the matching writer position under one lock.
    func appendRecord(_ makeLine: @Sendable (UInt64) -> String) -> Task<Bool, Never>? {
        state.withLock { state in
            guard !state.closed else { return nil }
            state.nextSequence &+= 1
            let line = makeLine(state.nextSequence)
            let previous = state.tail
            let sink = self.sink
            let task = Task.detached {
                _ = await previous?.value
                return await sink.append([line])
            }
            state.tail = task
            return task
        }
    }

    func appendTerminalRecord(_ makeLine: @Sendable (UInt64) -> String) -> Task<Bool, Never>? {
        state.withLock { state in
            guard !state.closed else { return nil }
            state.nextSequence &+= 1
            let line = makeLine(state.nextSequence)
            let previous = state.tail
            let sink = self.sink
            let task = Task.detached {
                _ = await previous?.value
                return await sink.appendTerminal([line])
            }
            state.tail = task
            return task
        }
    }

    func drain() async {
        let tail = state.withLock { $0.tail }
        _ = await tail?.value
    }

    /// Atomically makes the stream terminal and appends its final record. Late watchdog appends
    /// cannot appear after `runEnd` or reopen the closed file handle.
    func closeAfterAppending(_ makeFinalLine: @Sendable (UInt64) -> String) -> Task<Void, Never> {
        state.withLock { state in
            if state.closed { return Task {} }
            state.nextSequence &+= 1
            let line = makeFinalLine(state.nextSequence)
            state.closed = true
            let previous = state.tail
            let sink = self.sink
            let write = Task.detached {
                _ = await previous?.value
                return await sink.append([line])
            }
            state.tail = write
            return Task.detached {
                _ = await write.value
                await sink.close()
            }
        }
    }
}

/// Weak run-scoped coordination for live session samplers.
///
/// The coordinator is deliberately not a global owner of sessions or samplers. It only keeps
/// weak identities so terminal shutdown can flush what is still live without extending any
/// editor window's lifetime or running a repeating process-wide timer.
@MainActor
final class DiagnosticRunCoordinator {
    static let shared = DiagnosticRunCoordinator()

    private final class WeakSampler {
        weak var value: PerformanceSampler?
        init(_ value: PerformanceSampler) { self.value = value }
    }

    private var samplers: [WeakSampler] = []

    func register(_ sampler: PerformanceSampler) {
        samplers.removeAll { $0.value == nil }
        guard !samplers.contains(where: { $0.value === sampler }) else { return }
        samplers.append(WeakSampler(sampler))
    }

    func unregister(_ sampler: PerformanceSampler) {
        samplers.removeAll { $0.value == nil || $0.value === sampler }
    }

    var liveRegistrationCount: Int {
        samplers = samplers.filter { $0.value != nil }
        return samplers.count
    }

    func flushAndInvalidateAll() {
        let live = samplers.compactMap(\.value)
        for sampler in live { sampler.invalidate() }
        samplers.removeAll()
    }
}
