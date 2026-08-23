//
//  SpecCorpusTests.swift
//  Markdown EditorTests
//
//  COR-80 / REQ-132: the imported conformance corpus.
//

import Foundation
import Testing
@testable import Markdown_Editor

/// 1,324 examples imported verbatim from the CommonMark 0.31.2 and GFM 0.29 specifications, with
/// version, source URL, licence, SHA-256 and refresh command recorded in the manifest.
///
/// These drive the same **structural** properties the generated corpus drives. They are not an HTML
/// conformance oracle — the expected HTML is deliberately not imported, because this app is an
/// editor rather than a renderer and storing an expectation nobody asserts on is the decorative
/// evidence `docs/DECISIONS.md` warns about.
///
/// What they add over the generator: real syntax nobody would think to generate. Reference
/// definitions, entity edge cases, tab expansion, deeply nested containers, HTML blocks of all
/// seven kinds, and every construct the two specs argue about.
struct SpecCorpusTests {

    private struct Manifest: Decodable {
        struct Source: Decodable {
            let name: String
            let version: String
            let license: String
            let url: String
            let sha256: String
            let exampleCount: Int
        }
        struct Example: Decodable {
            let id: String
            let source: String
            let extensions: String
            let markdown: String
        }
        let schemaVersion: Int
        let purpose: String
        let refreshCommand: String
        let sources: [Source]
        let examples: [Example]
    }

    private static func loadManifest() throws -> Manifest {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Specifications/spec-corpus.json")
        return try JSONDecoder().decode(Manifest.self, from: try Data(contentsOf: url))
    }

    // Verifies: REQ-132 — the imported corpus carries its provenance. A corpus without version,
    // licence and digest is untraceable: nobody can tell what it is a corpus *of*, or whether it
    // still matches upstream.
    @Test func corpusCarriesCompleteProvenance() throws {
        let manifest = try Self.loadManifest()
        #expect(manifest.schemaVersion == 1)
        #expect(!manifest.refreshCommand.isEmpty)
        #expect(manifest.sources.count == 2)

        for source in manifest.sources {
            #expect(!source.version.isEmpty && source.version != "unknown", "\(source.name) has no version")
            #expect(source.license.contains("CC-BY-SA"), "\(source.name) licence not recorded")
            #expect(source.url.hasPrefix("https://"), "\(source.name) has no source URL")
            #expect(source.sha256.count == 64, "\(source.name) has no digest")
            #expect(source.exampleCount > 100)
        }

        // The pinned dialect is GFM 0.29, and the imported GFM spec must be that same version —
        // otherwise the corpus describes a dialect the parser is not configured for.
        let gfm = try #require(manifest.sources.first { $0.name.contains("GitHub") })
        #expect(gfm.version == "0.29", "imported GFM spec is \(gfm.version) but the app pins 0.29")

        #expect(manifest.examples.count == manifest.sources.reduce(0) { $0 + $1.exampleCount })
        #expect(manifest.examples.allSatisfy { !$0.markdown.isEmpty })
        #expect(Set(manifest.examples.map(\.id)).count == manifest.examples.count, "duplicate ids")
    }

    // Verifies: REQ-132/047 — every spec example parses without error and compiles to a projection
    // the independent `ProjectionOracle` accepts. This is the structural invariant that must hold
    // for *any* input: real Markdown from the specifications is the strongest available test of it.
    @Test func everySpecExampleParsesAndSatisfiesTheProjectionOracle() throws {
        let manifest = try Self.loadManifest()
        var failures: [String] = []

        for example in manifest.examples {
            guard let tree = try? MarkdownParser.parse(example.markdown, sourceVersion: 1).get() else {
                failures.append("\(example.id): parse failed for \(example.markdown.debugDescription)")
                continue
            }
            let index = MarkdownSourceIndex(source: example.markdown, sourceVersion: 1)
            let model = MarkdownProjectionModel.build(tree: tree, index: index)
            if case .failure(let reason) = ProjectionOracle.validate(
                model: model,
                sourceUTF16Count: (example.markdown as NSString).length
            ) {
                failures.append("\(example.id): oracle refused (\(reason)) for \(example.markdown.debugDescription)")
            }
        }

        #expect(failures.isEmpty, "\(failures.count) example(s) failed:\n\(failures.prefix(10).joined(separator: "\n"))")
    }

    /// COR-88 phase 1: the strengthening risk, retired before the oracle changes.
    ///
    /// The coverage-array oracle accepted out-of-order segments that happened to tile. Its tiling
    /// replacement does not. That is a *strengthening*, so it can only ship if production never
    /// emits out-of-order segments — and the pinned specification is the strongest available
    /// evidence for that, covering reference definitions, tab expansion, nested containers and
    /// all seven HTML block kinds that no generator here produces.
    ///
    /// // Verifies: REQ-132/054 — segments are emitted in ascending projection order.
    @Test func everySpecExampleEmitsSegmentsInAscendingProjectionOrder() throws {
        let manifest = try Self.loadManifest()
        var failures: [String] = []
        var segmentsSeen = 0

        for example in manifest.examples {
            guard let tree = try? MarkdownParser.parse(example.markdown, sourceVersion: 1).get() else {
                continue
            }
            let index = MarkdownSourceIndex(source: example.markdown, sourceVersion: 1)
            let model = MarkdownProjectionModel.build(tree: tree, index: index)
            segmentsSeen += model.segments.count
            var cursor = 0
            for segment in model.segments {
                let range = segment.projectionRange
                if range.location != cursor {
                    failures.append(
                        "\(example.id): segment at \(range.location) does not continue from \(cursor)"
                    )
                    break
                }
                cursor = NSMaxRange(range)
            }
        }

        // The detector proves itself: an empty corpus, or a corpus whose models carry no
        // segments, would make the loop above vacuous.
        #expect(segmentsSeen > 1_000, "only \(segmentsSeen) segments examined — the property would be vacuous")
        #expect(failures.isEmpty, "\(failures.count) example(s) out of order:\n\(failures.prefix(10).joined(separator: "\n"))")
    }

    // Verifies: REQ-132/051 — every token the source highlighter produces over the spec corpus lies
    // inside its document and never splits a composed character sequence. The oracle is `NSString`'s
    // own grapheme segmentation, which the highlighter does not use.
    @Test func everySpecExampleProducesContainedGraphemeAlignedTokens() async throws {
        let manifest = try Self.loadManifest()
        let highlighter = MarkdownHighlighter()
        var failures: [String] = []

        for example in manifest.examples {
            let ns = example.markdown as NSString
            let tokens = try await highlighter.tokens(for: example.markdown)
            for token in tokens {
                guard token.range.location >= 0, NSMaxRange(token.range) <= ns.length else {
                    failures.append("\(example.id): \(token.style) out of bounds \(NSStringFromRange(token.range))")
                    continue
                }
                guard token.range.length > 0 else { continue }
                let composed = ns.rangeOfComposedCharacterSequences(for: token.range)
                if !NSEqualRanges(composed, token.range) {
                    failures.append("\(example.id): \(token.style) splits a grapheme \(NSStringFromRange(token.range))")
                }
            }
        }

        #expect(failures.isEmpty, "\(failures.count) failure(s):\n\(failures.prefix(10).joined(separator: "\n"))")
    }

    // Verifies: REQ-041/045/132 — incremental lexing agrees with a fresh full relex over every spec
    // example, for a representative edit at the document start, middle and end. COR-84 repaired the
    // two divergences the generated corpus found; this asks the same question of real spec syntax,
    // which contains constructs no generator here produces.
    @Test func incrementalLexingAgreesWithFullRelexAcrossTheSpecCorpus() async throws {
        let manifest = try Self.loadManifest()
        var failures: [String] = []

        for example in manifest.examples {
            let ns = example.markdown as NSString
            guard ns.length > 0 else { continue }
            let offsets = [0, ns.length / 2, ns.length]

            for rawOffset in offsets {
                // Never split a composed character: an edit inside a grapheme is not an edit a user
                // can make, and a failure there would describe the harness.
                let offset = rawOffset >= ns.length
                    ? ns.length
                    : ns.rangeOfComposedCharacterSequence(at: rawOffset).location

                let highlighter = IncrementalSourceHighlighter()
                _ = try await highlighter.highlight(
                    source: example.markdown, editedRange: nil, sourceRevision: 1, intentID: nil
                )
                let mutable = NSMutableString(string: example.markdown)
                mutable.replaceCharacters(in: NSRange(location: offset, length: 0), with: "x")
                let edited = mutable as String

                let patch = try await highlighter.highlight(
                    source: edited,
                    editedRange: NSRange(location: offset, length: 1),
                    sourceRevision: 2,
                    intentID: nil
                )
                let full = try await MarkdownHighlighter().tokens(for: edited)

                for changed in patch.changedRanges {
                    let incremental = TokenCanonicalization.canonical(
                        TokenCanonicalization.clipped(patch.tokens, to: changed)
                    )
                    let expected = TokenCanonicalization.canonical(
                        TokenCanonicalization.clipped(full, to: changed)
                    )
                    if incremental != expected {
                        failures.append("""
                            \(example.id) insert@\(offset) in \(NSStringFromRange(changed))
                              source: \(example.markdown.debugDescription)
                              incr: \(incremental)
                              full: \(expected)
                            """)
                    }
                }
            }
        }

        #expect(failures.isEmpty, "\(failures.count) divergence(s):\n\(failures.prefix(5).joined(separator: "\n"))")
    }
}
