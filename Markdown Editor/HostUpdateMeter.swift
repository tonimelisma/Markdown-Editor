//
//  HostUpdateMeter.swift
//  Markdown Editor
//

import Foundation

/// Counts editor-host view updates in a rolling one-second window.
///
/// // REQ-096; ARC-Q11: an idle document performs a bounded number of host updates. A sustained
/// // rate above the threshold means reconciliation is feeding itself and is reported as a fault.
@MainActor
final class HostUpdateMeter {
    /// Updates per second above which reconciliation is not explainable by user input.
    /// A trackpad scroll or fast typing produces far fewer host updates than this.
    static let stormThreshold = 120

    private(set) var updatesInWindow = 0
    private(set) var stormReported = false
    private var windowStartUptime: UInt64

    init() {
        windowStartUptime = DispatchTime.now().uptimeNanoseconds
    }

    /// Result of one completed host update.
    struct Sample {
        let durationNanos: UInt64
        let updatesInWindow: Int
        /// True on the update that first crosses the threshold in this window.
        let crossedStormThreshold: Bool
    }

    func record(durationNanos: UInt64) -> Sample {
        let now = DispatchTime.now().uptimeNanoseconds
        if now &- windowStartUptime >= 1_000_000_000 {
            windowStartUptime = now
            updatesInWindow = 0
            stormReported = false
        }
        updatesInWindow += 1
        var crossed = false
        if updatesInWindow > Self.stormThreshold, !stormReported {
            stormReported = true
            crossed = true
        }
        return Sample(
            durationNanos: durationNanos,
            updatesInWindow: updatesInWindow,
            crossedStormThreshold: crossed
        )
    }
}
