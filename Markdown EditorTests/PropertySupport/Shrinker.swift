//
//  Shrinker.swift
//  Markdown EditorTests
//

import Foundation

/// Deterministic shrinking for a failing generated document.
///
/// // REQ-132: "retain each minimized discovered failure as a regression fixture". A 233-character
/// // generated document that reproduces a defect is evidence; the four-line reduction of it is a
/// // fixture someone can read, and the difference between the two is whether the defect ever gets
/// // understood. COR-80's first findings were characterised by hand precisely because this did not
/// // exist yet.
///
/// Deliberately not a general-purpose shrinker. It applies a fixed ladder of Markdown-aware
/// reductions, each of which either still reproduces (keep it) or does not (discard it), and stops
/// when a full pass makes no progress. Fixed order and no randomness, so the same failure always
/// minimizes to the same fixture.
enum Shrinker {

    /// Reduces `source` while `stillFails` keeps returning true.
    ///
    /// - Parameter budget: maximum candidate evaluations. A shrinker that can run unboundedly turns
    ///   one failing property into a hung suite.
    static func minimize(
        _ source: String,
        budget: Int = 2_000,
        stillFails: (String) -> Bool
    ) -> String {
        guard stillFails(source) else { return source }
        var best = source
        var evaluations = 0

        func tryCandidate(_ candidate: String) -> Bool {
            guard evaluations < budget, candidate != best, !candidate.isEmpty else { return false }
            evaluations += 1
            guard stillFails(candidate) else { return false }
            best = candidate
            return true
        }

        var progressed = true
        while progressed && evaluations < budget {
            progressed = false

            // 1. Drop whole lines, last first. Removing from the end keeps earlier context stable,
            //    which makes the ladder converge instead of oscillating.
            var lines = best.components(separatedBy: "\n")
            var index = lines.count - 1
            while index >= 0 && evaluations < budget {
                var candidate = lines
                candidate.remove(at: index)
                if tryCandidate(candidate.joined(separator: "\n")) {
                    lines = best.components(separatedBy: "\n")
                    index = min(index, lines.count - 1)
                    progressed = true
                } else {
                    index -= 1
                }
            }

            // 2. Halve the document, keeping whichever half still reproduces. Cheap way out of a
            //    long run of independent lines that step 1 would remove one at a time.
            let allLines = best.components(separatedBy: "\n")
            if allLines.count > 3 {
                let middle = allLines.count / 2
                if tryCandidate(allLines.prefix(middle).joined(separator: "\n"))
                    || tryCandidate(allLines.suffix(from: middle).joined(separator: "\n")) {
                    progressed = true
                }
            }

            // 3. Simplify inline content to a marker, so the fixture shows structure rather than
            //    the generator's filler text.
            for noisy in ["the quick brown fox", "bravo charlie", "naïve résumé", "Grüße", "ñandú"] {
                if best.contains(noisy), tryCandidate(best.replacingOccurrences(of: noisy, with: "x")) {
                    progressed = true
                }
            }

            // 4. Remove the BOM, which is often incidental to a failure that mentions it.
            if best.hasPrefix("\u{FEFF}"), tryCandidate(String(best.dropFirst())) {
                progressed = true
            }
        }

        return best
    }

    /// Async variant. The properties worth shrinking in this project — incremental lexing against a
    /// fresh relex — are `async`, so a sync-only shrinker would force every caller through a
    /// semaphore bridge that Swift 6 rejects as a data race.
    static func minimize(
        _ source: String,
        budget: Int = 2_000,
        stillFails: (String) async -> Bool
    ) async -> String {
        guard await stillFails(source) else { return source }
        var best = source
        var evaluations = 0

        func tryCandidate(_ candidate: String) async -> Bool {
            guard evaluations < budget, candidate != best, !candidate.isEmpty else { return false }
            evaluations += 1
            guard await stillFails(candidate) else { return false }
            best = candidate
            return true
        }

        var progressed = true
        while progressed && evaluations < budget {
            progressed = false

            var lines = best.components(separatedBy: "\n")
            var index = lines.count - 1
            while index >= 0 && evaluations < budget {
                var candidate = lines
                candidate.remove(at: index)
                if await tryCandidate(candidate.joined(separator: "\n")) {
                    lines = best.components(separatedBy: "\n")
                    index = min(index, lines.count - 1)
                    progressed = true
                } else {
                    index -= 1
                }
            }

            let allLines = best.components(separatedBy: "\n")
            if allLines.count > 3 {
                let middle = allLines.count / 2
                if await tryCandidate(allLines.prefix(middle).joined(separator: "\n")) {
                    progressed = true
                } else if await tryCandidate(allLines.suffix(from: middle).joined(separator: "\n")) {
                    progressed = true
                }
            }

            for noisy in ["the quick brown fox", "bravo charlie", "naïve résumé", "Grüße", "ñandú"] {
                if best.contains(noisy), await tryCandidate(best.replacingOccurrences(of: noisy, with: "x")) {
                    progressed = true
                }
            }

            if best.hasPrefix("\u{FEFF}"), await tryCandidate(String(best.dropFirst())) {
                progressed = true
            }
        }

        return best
    }
}
