import Foundation
import Synchronization

/// A sendable sequence allocator shared by main-actor and watchdog records.
final class DiagnosticSequence: Sendable {
    private let state = Mutex<UInt64>(0)

    func next() -> UInt64 {
        state.withLock { value in
            value &+= 1
            return value
        }
    }

    var current: UInt64 { state.withLock { $0 } }
}

/// Serializes all file writes, including records produced while the main actor is blocked.
final class DiagnosticWriteCoordinator: Sendable {
    private struct State {
        var tail: Task<Bool, Never>?
    }

    private let state = Mutex(State(tail: nil))
    private let sink: DiagnosticFileSink

    init(sink: DiagnosticFileSink) {
        self.sink = sink
    }

    func append(_ lines: [String]) -> Task<Bool, Never> {
        state.withLock { state in
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

    func drain() async {
        let tail = state.withLock { $0.tail }
        _ = await tail?.value
    }

    func closeAfterDrain() -> Task<Void, Never> {
        let tail = state.withLock { $0.tail }
        let sink = self.sink
        return Task.detached {
            _ = await tail?.value
            await sink.close()
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
