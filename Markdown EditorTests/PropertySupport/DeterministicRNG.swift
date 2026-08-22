//
//  DeterministicRNG.swift
//  Markdown EditorTests
//

import Foundation

/// SplitMix64. Seeded, reproducible, and independent of the platform's `SystemRandomNumberGenerator`,
/// whose sequence is not stable across processes or OS versions.
///
/// // REQ-132: every generated case must be replayable from its printed seed. A property that
/// // cannot be replayed reports a failure nobody can act on.
struct DeterministicRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in `0..<bound`.
    mutating func next(below bound: Int) -> Int {
        precondition(bound > 0)
        return Int(next() % UInt64(bound))
    }

    mutating func pick<T>(_ values: [T]) -> T {
        values[next(below: values.count)]
    }

    mutating func bool() -> Bool {
        next() & 1 == 0
    }
}
