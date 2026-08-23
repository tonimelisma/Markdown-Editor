//
//  ProjectionOracleTests.swift
//  Markdown EditorTests
//

import Foundation
import Testing
@testable import Markdown_Editor

/// The projection oracle's rejection behaviour, on hand-built segment sets.
///
/// // Verifies: REQ-054/055/056/091 — the oracle refuses a projection that does not exactly
/// partition its rendered text.
///
/// Deliberately hand-built rather than corpus-driven: a corpus proves the oracle *accepts* real
/// projections, which is what `SpecCorpusTests` does. Nothing there can show the oracle would
/// still reject a broken one, and an oracle that accepts everything is the failure mode that
/// makes every other proof in this repository weaker.
struct ProjectionOracleTests {

    /// A model whose segments are exactly the ranges given, over `rendered`.
    private func model(rendered: String, segments: [NSRange]) -> MarkdownProjectionModel {
        MarkdownProjectionModel(
            sourceVersion: 1,
            renderedString: rendered,
            runs: [],
            attachments: [],
            tables: [],
            blocks: [],
            segments: segments.map {
                .source(projection: $0, source: $0, insertionBefore: $0.location, insertionAfter: NSMaxRange($0))
            },
            listMarkers: [],
            sourceUTF16Count: (rendered as NSString).length
        )
    }

    private func failureCode(_ model: MarkdownProjectionModel) -> String? {
        switch ProjectionOracle.validate(
            model: model,
            sourceUTF16Count: model.sourceUTF16Count
        ) {
        case .success: return nil
        case .failure(let failure): return failure.code
        }
    }

    /// The control. Without this, every rejection below could be produced by an oracle that
    /// refuses unconditionally.
    @Test func exactlyTilingSegmentsAreAccepted() {
        let m = model(rendered: "abcdef", segments: [
            NSRange(location: 0, length: 3),
            NSRange(location: 3, length: 3),
        ])
        #expect(failureCode(m) == nil)
    }

    @Test func overlappingSegmentsAreRejected() {
        let m = model(rendered: "abcdef", segments: [
            NSRange(location: 0, length: 4),
            NSRange(location: 3, length: 3),
        ])
        #expect(failureCode(m) == "overlap")
    }

    @Test func aGapBetweenSegmentsIsRejected() {
        let m = model(rendered: "abcdef", segments: [
            NSRange(location: 0, length: 2),
            NSRange(location: 3, length: 3),
        ])
        #expect(failureCode(m) == "gap")
    }

    /// Coverage that stops short of the rendered text. The old coverage array caught this with
    /// `firstIndex(where: { $0 == 0 })`; the tiling check catches it as a short final cursor.
    @Test func segmentsThatDoNotReachTheEndAreRejected() {
        let m = model(rendered: "abcdef", segments: [
            NSRange(location: 0, length: 3),
        ])
        #expect(failureCode(m) == "gap")
    }

    /// A projection range past the rendered text, with an in-bounds source range — so the
    /// failure is attributed to the projection space rather than to the source space, which the
    /// oracle checks first.
    @Test func segmentsPastTheRenderedLengthAreRejected() {
        let rendered = "abcdef"
        let m = MarkdownProjectionModel(
            sourceVersion: 1,
            renderedString: rendered,
            runs: [],
            attachments: [],
            tables: [],
            blocks: [],
            segments: [
                .source(projection: NSRange(location: 0, length: 3), source: NSRange(location: 0, length: 3), insertionBefore: 0, insertionAfter: 3),
                .source(projection: NSRange(location: 3, length: 9), source: NSRange(location: 3, length: 3), insertionBefore: 3, insertionAfter: 6),
            ],
            listMarkers: [],
            sourceUTF16Count: (rendered as NSString).length
        )
        #expect(failureCode(m) == "proj_oob")
    }

    /// The behaviour the coverage array could not see.
    ///
    /// These two segments cover `0..<6` exactly once between them, so the old per-character
    /// oracle accepted them: every index was covered exactly once and no index was zero. They are
    /// nonetheless emitted out of order, which every consumer of `segments` — the coordinate map,
    /// atom construction, selection mapping — assumes cannot happen.
    ///
    /// // This is the test that must fail against the pre-COR-88 implementation.
    @Test func outOfOrderSegmentsAreRejectedEvenThoughTheyCoverExactlyOnce() {
        let m = model(rendered: "abcdef", segments: [
            NSRange(location: 3, length: 3),
            NSRange(location: 0, length: 3),
        ])
        #expect(failureCode(m) == "out_of_order", "out-of-order segments were accepted")
    }

    /// An empty projection is legitimately empty, not a gap.
    @Test func anEmptyProjectionWithNoSegmentsIsAccepted() {
        #expect(failureCode(model(rendered: "", segments: [])) == nil)
    }

    /// A segment whose *source* range leaves the document is rejected even when its projection
    /// tiles correctly — the two coordinate spaces are checked independently.
    @Test func sourceRangeOutOfBoundsIsRejected() {
        let rendered = "abcdef"
        let m = MarkdownProjectionModel(
            sourceVersion: 1,
            renderedString: rendered,
            runs: [],
            attachments: [],
            tables: [],
            blocks: [],
            segments: [
                .source(
                    projection: NSRange(location: 0, length: 6),
                    source: NSRange(location: 0, length: 99),
                    insertionBefore: 0,
                    insertionAfter: 6
                )
            ],
            listMarkers: [],
            sourceUTF16Count: (rendered as NSString).length
        )
        #expect(failureCode(m) == "source_oob")
    }

    /// The oracle's cost must not scale with document length.
    ///
    /// // Verifies: REQ-143's mechanism — a *shape* assertion, not a wall-clock threshold, so it
    /// encodes no machine's speed and cannot go flaky. Two projections with identical segment
    /// counts and a 1000x difference in character count must cost about the same. The pre-COR-88
    /// coverage array allocated and walked one slot per character, so it failed this by roughly
    /// three orders of magnitude.
    @Test func oracleCostDoesNotScaleWithDocumentLength() {
        func elapsedNanos(characters: Int) -> UInt64 {
            let rendered = String(repeating: "a", count: characters)
            let half = characters / 2
            let m = model(rendered: rendered, segments: [
                NSRange(location: 0, length: half),
                NSRange(location: half, length: characters - half),
            ])
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<20 { _ = failureCode(m) }
            return DispatchTime.now().uptimeNanoseconds &- start
        }

        // Warm up, so neither measurement pays one-time costs the other avoids.
        _ = elapsedNanos(characters: 100)

        let small = elapsedNanos(characters: 100)
        let large = elapsedNanos(characters: 100_000)

        // Generous: the claim is "does not scale with length", and at 1000x the characters even a
        // 20x ratio would prove that. The array formulation exceeded this by orders of magnitude.
        #expect(
            large < small * 20 + 1_000_000,
            "oracle cost scales with document length: 100 chars \\(small) ns, 100k chars \\(large) ns"
        )
    }
}
