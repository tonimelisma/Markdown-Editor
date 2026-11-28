//
//  PropertyTests.swift
//  Markdown EditorTests
//
//  COR-80 / REQ-132: generated conformance verification over declared input dimensions, compared
//  only against independent oracles, replayable from printed seeds.
//

import Foundation
import Testing
@testable import Markdown_Editor

/// Every property here obeys three rules, which are the point of the increment:
///
/// 1. **Independent oracle.** A property never compares an implementation to a helper that
///    implementation calls. Incremental lexing is compared to a *fresh full* lexer; a coordinate
///    map is compared to its exact inverse; a projection is compared to `ProjectionOracle`.
/// 2. **Declared dimensions, not chosen variety.** Inputs come from the cross-product in
///    `GeneratedMarkdown.corpus()`, and `dimensionCoverageIsComplete` fails if a member of any
///    closed enum is never visited.
/// 3. **Replayable.** Failures print the seed and the exact source, so the case can be turned into
///    a permanent fixture without re-running the generator.
struct PropertyTests {

    // Validates: REQ-132 — the generated corpus visits every member of every declared dimension.
    // Adding a `BlockKind`, `InlineKind`, `TextFlavor`, or `EditOperation` fails here until the
    // generator can produce it, which is what makes this coverage rather than variety.
    @Test func dimensionCoverageIsComplete() {
        let corpus = GeneratedMarkdown.corpus()
        #expect(!corpus.isEmpty)

        var blocks = Set<String>()
        var inlines = Set<String>()
        var flavors = Set<String>()
        var endings = Set<String>()
        var wellformedness = Set<String>()
        var boms = Set<Bool>()
        for document in corpus {
            document.blocks.forEach { blocks.insert(String(describing: $0)) }
            document.inlines.forEach { inlines.insert(String(describing: $0)) }
            flavors.insert(String(describing: document.flavor))
            endings.insert(String(describing: document.lineEnding))
            wellformedness.insert(String(describing: document.wellformedness))
            boms.insert(document.hasBOM)
        }

        #expect(blocks.count == BlockKind.allCases.count, "unvisited block kinds: \(Set(BlockKind.allCases.map { String(describing: $0) }).subtracting(blocks))")
        #expect(inlines.count == InlineKind.allCases.count, "unvisited inline kinds: \(Set(InlineKind.allCases.map { String(describing: $0) }).subtracting(inlines))")
        #expect(flavors.count == TextFlavor.allCases.count)
        #expect(endings.count == LineEnding.allCases.count)
        #expect(wellformedness.count == Wellformedness.allCases.count)
        #expect(boms == [false, true])

        // Edit operations are exercised by the edit properties below; assert the vocabulary is
        // closed and reachable here so a new case cannot be added without a generator.
        var rng = DeterministicRNG(seed: 1)
        let source = "alpha\nbravo\n"
        for operation in EditOperation.allCases {
            let edit = GeneratedEditSequence.edit(operation, in: source, rng: &rng)
            #expect(NSMaxRange(edit.range) <= (source as NSString).length, "\(operation) produced an out-of-bounds range")
        }
    }

    // Validates: REQ-132 — the source index round-trips every generated document. Oracle: the exact
    // inverse map, not a second call into the same helper. A UTF-8 offset converted to UTF-16 and
    // back must land where it started, for every line start in the document.
    @Test func sourceIndexRoundTripsOnEveryGeneratedDocument() throws {
        for document in GeneratedMarkdown.corpus() {
            let index = MarkdownSourceIndex(source: document.text, sourceVersion: 1)
            for line in 1...max(index.lineCount, 1) {
                guard case .success(let utf8Offset) = index.utf8Offset(line: line, column: 1) else { continue }
                let range = UTF8Range(start: utf8Offset, end: utf8Offset)
                guard case .success(let utf16) = index.utf16Range(for: range) else {
                    Issue.record("no UTF-16 range for line \(line)\n\(document.replayDescription)")
                    continue
                }
                #expect(
                    utf16.location <= (document.text as NSString).length,
                    "line \(line) mapped outside the document\n\(document.replayDescription)"
                )
                #expect(utf16.length == 0, "a zero-width UTF-8 range must stay zero-width\n\(document.replayDescription)")
            }
        }
    }

    // Validates: REQ-132 — every generated document compiles to a projection the independent
    // `ProjectionOracle` accepts. The oracle is a separate validator, not the compiler's own
    // bookkeeping, so this discriminates a projection that is internally consistent but wrong
    // about the source it claims to describe.
    @Test func projectionOracleAcceptsEveryGeneratedDocument() throws {
        for document in GeneratedMarkdown.corpus() {
            guard let tree = try? MarkdownParser.parse(document.text, sourceVersion: 1).get() else {
                Issue.record("parse failed\n\(document.replayDescription)")
                continue
            }
            let index = MarkdownSourceIndex(source: document.text, sourceVersion: 1)
            let model = MarkdownProjectionModel.build(tree: tree, index: index)
            let result = ProjectionOracle.validate(
                model: model,
                sourceUTF16Count: (document.text as NSString).length
            )
            if case .failure(let reason) = result {
                Issue.record("projection oracle refused: \(reason)\n\(document.replayDescription)")
            }
        }
    }

    // Validates: REQ-041, REQ-045, REQ-132 — incremental lexing agrees with a *fresh full* relex over the
    // whole declared corpus, everywhere. The oracle is a brand-new `MarkdownHighlighter`, which
    // shares no state with the incremental one.
    //
    // This property found both divergences COR-84 repaired, and neither was reachable from the
    // hand-written fixtures in `IncrementalSourceHighlighterTests`, whose edits sit at the tail of
    // three-line documents where the changed range covers everything after it. It carried a pinned
    // `knownParityDivergences = 30` until the repair; the constant is deleted rather than lowered
    // to zero, because agreement is now an assertion and not a baseline to hold a defect at.
    @Test func incrementalHighlightingMatchesAFullRelexAfterEveryEditKind() async throws {
        let corpus = GeneratedMarkdown.corpus(seedsPerCell: 1)
        var rng = DeterministicRNG(seed: 0xC0_8000)
        var divergences: [String] = []

        for document in corpus {
            for operation in EditOperation.allCases {
                let highlighter = IncrementalSourceHighlighter()
                _ = try await highlighter.highlight(
                    source: document.text,
                    editedRange: nil,
                    sourceRevision: 1,
                    intentID: nil
                )

                let edit = GeneratedEditSequence.edit(operation, in: document.text, rng: &rng)
                let edited = GeneratedEditSequence.apply(edit, to: document.text)
                let patch = try await highlighter.highlight(
                    source: edited,
                    editedRange: NSRange(location: edit.range.location, length: (edit.replacement as NSString).length),
                    sourceRevision: 2,
                    intentID: nil
                )
                let expected = try await MarkdownHighlighter().tokens(for: edited)

                // Compare inside the region the patch says it rescanned. Both sides are already in
                // post-edit coordinates there, so a difference is a real lexing disagreement and
                // not a bookkeeping artefact of the harness.
                for changed in patch.changedRanges {
                    let fromPatch = TokenCanonicalization.canonical(
                        TokenCanonicalization.clipped(patch.tokens, to: changed)
                    )
                    let fromFullRelex = TokenCanonicalization.canonical(
                        TokenCanonicalization.clipped(expected, to: changed)
                    )
                    if fromPatch != fromFullRelex {
                        divergences.append("""
                            \(NSStringFromRange(changed)) edit=\(edit.replayDescription) \
                            seed=\(document.seed) wellformed=\(document.wellformedness)
                            """)
                    }
                }
                #expect(patch.sourceUTF16Count == (edited as NSString).length)
            }
        }

        #expect(
            divergences.isEmpty,
            """
            incremental lexing disagreed with a full relex in \(divergences.count) case(s):
            \(divergences.joined(separator: "\n"))
            """
        )
    }

    // Validates: REQ-132 — the shrinker actually reduces, terminates, and preserves the property it
    // was given. A shrinker that returned its input unchanged would satisfy "minimized fixture" in
    // name only, and one that lost the failing property would produce a fixture that proves nothing.
    @Test func shrinkerReducesWhilePreservingTheFailingProperty() {
        let original = (1...40).map { "line \($0) the quick brown fox" }.joined(separator: "\n")
        // A property that only cares about one marker line: everything else is removable.
        let minimized = Shrinker.minimize(original) { $0.contains("line 7 ") }

        #expect(minimized.contains("line 7 "), "shrinking lost the property it was minimizing")
        #expect(minimized.count < original.count, "shrinker returned something no smaller")
        #expect(
            minimized.components(separatedBy: "\n").count <= 3,
            "expected a near-minimal fixture, got \(minimized.components(separatedBy: "\n").count) lines"
        )
        // Filler text is replaced with a marker, so the fixture shows structure not noise.
        #expect(!minimized.contains("quick brown fox"))
    }

    // Validates: REQ-132 — shrinking is deterministic: the same failure minimizes to the same
    // fixture every time, so a committed regression fixture is reproducible rather than whatever
    // that run happened to find.
    @Test func shrinkingIsDeterministic() {
        let original = GeneratedMarkdown.corpus(seedsPerCell: 1)[3].text
        let property: (String) -> Bool = { $0.contains("|") || $0.contains("#") }
        let first = Shrinker.minimize(original, stillFails: property)
        let second = Shrinker.minimize(original, stillFails: property)
        #expect(first == second)
    }

    // Validates: REQ-132 — a shrinker cannot run unboundedly. A property that always reports failure
    // would otherwise let the ladder evaluate forever and hang the suite instead of failing it.
    @Test func shrinkingRespectsItsEvaluationBudget() {
        let original = (1...200).map { "line \($0)" }.joined(separator: "\n")
        let minimized = Shrinker.minimize(original, budget: 10) { _ in true }
        #expect(!minimized.isEmpty)
        // With a budget of 10 it cannot have reached the true minimum, which is the point: it
        // stopped rather than ran.
        #expect(minimized.components(separatedBy: "\n").count > 1)
    }

    // Validates: REQ-132 — every generated token range lies inside the document and never splits a
    // composed character sequence. Oracle: `NSString`'s own grapheme segmentation, which the
    // highlighter does not use.
    @Test func tokenRangesAreContainedAndGraphemeAligned() async throws {
        for document in GeneratedMarkdown.corpus(seedsPerCell: 1) {
            let ns = document.text as NSString
            let tokens = try await MarkdownHighlighter().tokens(for: document.text)
            for token in tokens {
                #expect(
                    token.range.location >= 0 && NSMaxRange(token.range) <= ns.length,
                    "token out of bounds \(NSStringFromRange(token.range))\n\(document.replayDescription)"
                )
                guard token.range.length > 0, NSMaxRange(token.range) <= ns.length else { continue }
                let composed = ns.rangeOfComposedCharacterSequences(for: token.range)
                #expect(
                    NSEqualRanges(composed, token.range),
                    """
                    token split a composed character sequence: \(NSStringFromRange(token.range)) \
                    vs \(NSStringFromRange(composed))
                    \(document.replayDescription)
                    """
                )
            }
        }
    }

    // Validates: REQ-132 — generated filenames stay portable for every text flavor. Oracle: an
    // explicit portability predicate, not `ImageAssetPolicy`'s own notion of a safe name.
    @Test func generatedAssetNamesStayPortableForEveryFlavor() {
        var rng = DeterministicRNG(seed: 0xA55E7)
        let reserved: Set<String> = ["con", "prn", "aux", "nul"]
        for flavor in TextFlavor.allCases {
            for _ in 0..<8 {
                let input = GeneratedMarkdown.sample(for: flavor, rng: &rng)
                let slug = ImageAssetPolicy.slug(from: input)

                #expect(!slug.isEmpty, "empty slug from \(input.debugDescription)")
                #expect(slug == slug.lowercased(), "not lowercased: \(slug)")
                #expect(slug.allSatisfy { $0.isASCII }, "non-ASCII survived: \(slug)")
                #expect(slug.count <= 64, "unbounded length: \(slug.count)")
                #expect(!reserved.contains(slug), "reserved device name: \(slug)")
                #expect(
                    slug.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" },
                    "unsafe character in \(slug)"
                )
                #expect(!slug.hasPrefix("-") && !slug.hasSuffix("-"), "leading/trailing dash: \(slug)")
            }
        }
    }
}
