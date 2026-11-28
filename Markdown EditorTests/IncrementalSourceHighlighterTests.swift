//
//  IncrementalSourceHighlighterTests.swift
//  Markdown EditorTests
//

import Foundation
import Testing
@testable import Markdown_Editor

struct IncrementalSourceHighlighterTests {
    // Validates: REQ-040, REQ-041, REQ-043 — the line lexer carries a fence state and does not style code
    // content as inline Markdown until the matching closer is observed.
    @Test func fenceStatePropagatesAndClosesOnMatchingFence() async throws {
        let source = "before *style*\n```swift\ninside **literal**\n```\nafter `code`\n"
        let highlighter = IncrementalSourceHighlighter()
        let patch = try await highlighter.highlight(
            source: source,
            editedRange: nil,
            sourceRevision: 1,
            intentID: nil
        )
        let ns = source as NSString
        let inside = ns.range(of: "inside **literal**")
        let after = ns.range(of: "after `code`")
        #expect(patch.tokens.contains { $0.style == .codeBlock && NSIntersectionRange($0.range, inside).length > 0 })
        #expect(patch.tokens.contains { $0.style == .inlineCode && NSIntersectionRange($0.range, after).length > 0 })
        #expect(!patch.tokens.contains { $0.style == .bold && NSIntersectionRange($0.range, inside).length > 0 })
    }

    // Validates: REQ-045 — a local paragraph edit stops after the incoming/outgoing lexical state
    // is unchanged and emits one exact changed-line range.
    @Test func ordinaryEditStopsAtStableTail() async throws {
        let source = (0..<120).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let highlighter = IncrementalSourceHighlighter()
        _ = try await highlighter.highlight(source: source, editedRange: nil, sourceRevision: 1, intentID: nil)
        let location = (source as NSString).range(of: "line 60").location
        let changedValue = NSMutableString(string: source)
        changedValue.replaceCharacters(in: NSRange(location: location, length: 1), with: "L")
        let changed = changedValue as String
        let patch = try await highlighter.highlight(
            source: changed,
            editedRange: NSRange(location: location, length: 1),
            sourceRevision: 2,
            intentID: IntentID(rawValue: 9)
        )
        #expect(patch.scannedLineCount <= 2)
        #expect(patch.changedRanges == [SourceLineIndex(source: changed).lines[60]])
        #expect(patch.lexedUTF16Count < (changed as NSString).length / 10)
        #expect(patch.intentID == IntentID(rawValue: 9))
    }

    // Validates: REQ-040, REQ-045 — CRLF and Unicode remain UTF-16 bounded across line patches.
    @Test func lineRangesRemainUTF16ExactForCRLFAndUnicode() async throws {
        let source = "🐙 **one**\r\nsecond\r\n"
        let highlighter = IncrementalSourceHighlighter()
        let patch = try await highlighter.highlight(source: source, editedRange: nil, sourceRevision: 3, intentID: nil)
        let length = (source as NSString).length
        #expect(patch.changedRanges.allSatisfy { $0.location >= 0 && NSMaxRange($0) <= length })
        #expect(patch.tokens.allSatisfy { $0.range.location >= 0 && NSMaxRange($0.range) <= length })
        #expect(SourceLineIndex(source: source).lines.map(\.length) == [12, 8])
    }

    // Validates: REQ-040, REQ-045 — an edit that grows a terminal newline uses the topology fallback
    // instead of treating the old final line as the complete new source.
    @Test func terminalNewlineGrowthRebuildsLineTopology() {
        let previous = SourceLineIndex(source: "one\n")
        let updated = SourceLineIndex.updating(
            source: "one\ntwo\n",
            previousSource: "one\n",
            previous: previous,
            editedRange: NSRange(location: 4, length: 4)
        )
        #expect(updated.lines == [NSRange(location: 0, length: 4), NSRange(location: 4, length: 4)])
    }

    // Validates: REQ-040, REQ-045 — deleting the final line cannot leave a phantom zero-length line
    // in the cached UTF-16 topology.
    @Test func terminalLineDeletionRebuildsLineTopology() {
        let previous = SourceLineIndex(source: "one\ntwo\n")
        let updated = SourceLineIndex.updating(
            source: "one\n",
            previousSource: "one\ntwo\n",
            previous: previous,
            editedRange: NSRange(location: 4, length: 0)
        )
        #expect(updated.lines == [NSRange(location: 0, length: 4)])
    }

    // Validates: REQ-041, REQ-043 — multiline GFM strikethrough state crosses a soft line break and
    // terminates on the matching delimiter without requiring a whole-source lexer.
    @Test func multilineStrikethroughStatePropagatesAcrossLines() async throws {
        let source = "before ~~first line\nsecond line~~ after\n"
        let highlighter = IncrementalSourceHighlighter()
        let patch = try await highlighter.highlight(source: source, editedRange: nil, sourceRevision: 4, intentID: nil)
        let ns = source as NSString
        let first = ns.range(of: "~~first line")
        let second = ns.range(of: "second line~~")
        #expect(patch.tokens.contains { $0.style == .strikethrough && NSIntersectionRange($0.range, first).length == first.length })
        #expect(patch.tokens.contains { $0.style == .strikethrough && NSIntersectionRange($0.range, second).length == second.length })
    }

    // Validates: REQ-041, REQ-045 — after the cache is seeded, an ordinary edit still carries the
    // unmatched GFM delimiter state into the following line.
    @Test func ordinaryEditCarriesMultilineStrikethroughState() async throws {
        let source = "before ~~first line\nsecond line~~ after\n"
        let highlighter = IncrementalSourceHighlighter()
        _ = try await highlighter.highlight(source: source, editedRange: nil, sourceRevision: 8, intentID: nil)
        let location = (source as NSString).range(of: "second").location
        let mutable = NSMutableString(string: source)
        mutable.replaceCharacters(in: NSRange(location: location, length: 6), with: "Second")
        let updated = mutable as String
        let patch = try await highlighter.highlight(
            source: updated,
            editedRange: NSRange(location: location, length: 6),
            sourceRevision: 9,
            intentID: nil
        )
        let second = (updated as NSString).range(of: "Second line~~")
        #expect(patch.tokens.contains { $0.style == .strikethrough && NSIntersectionRange($0.range, second).length == second.length })
    }

    // Validates: REQ-041 — escaped and unmatched tilde runs remain literal, while a later
    // multiline span remains discoverable after an earlier completed span.
    @Test func strikethroughMatchesFormalGFMDelimiterRuns() async throws {
        let source = "~~not\\~~\n~~open~\n\n~~one~~ and ~~two\nthree~~\n"
        let patch = try await IncrementalSourceHighlighter().highlight(
            source: source,
            editedRange: nil,
            sourceRevision: 5,
            intentID: nil
        )
        let ns = source as NSString
        let escaped = ns.range(of: "~~not\\~~")
        let unmatched = ns.range(of: "~~open~")
        let first = ns.range(of: "~~one~~")
        let later = ns.range(of: "~~two\nthree~~")
        #expect(!patch.tokens.contains { $0.style == .strikethrough && NSIntersectionRange($0.range, escaped).length > 0 })
        #expect(!patch.tokens.contains { $0.style == .strikethrough && NSIntersectionRange($0.range, unmatched).length > 0 })
        #expect(patch.tokens.contains { $0.style == .strikethrough && NSIntersectionRange($0.range, first).length == first.length })
        let laterCoverage = patch.tokens
            .filter { $0.style == .strikethrough }
            .reduce(into: 0) { total, token in total += NSIntersectionRange(token.range, later).length }
        #expect(laterCoverage == later.length)
    }

    // Validates: REQ-041, REQ-045 — a sequence of edits has the same token result as a fresh full
    // lexer, including a multiline delimiter closure and a fence opening/closure.
    @Test func editSequenceMatchesFreshFullLexer() async throws {
        let highlighter = IncrementalSourceHighlighter()
        var source = "title\n~~open\nplain\n"
        var incrementalTokens = try await highlighter.highlight(
            source: source,
            editedRange: nil,
            sourceRevision: 1,
            intentID: nil
        ).tokens

        let edits: [(String, String)] = [
            ("open", "closed~~"),
            ("plain", "```\nplain"),
            ("plain\n", "plain\n```\n")
        ]

        for (needle, replacement) in edits {
            let range = (source as NSString).range(of: needle)
            let mutable = NSMutableString(string: source)
            mutable.replaceCharacters(in: range, with: replacement)
            source = mutable as String
            let changedRange = NSRange(location: range.location, length: (replacement as NSString).length)
            let patch = try await highlighter.highlight(
                source: source,
                editedRange: changedRange,
                sourceRevision: UInt64(incrementalTokens.count + source.utf16.count),
                intentID: nil
            )
            incrementalTokens.removeAll { token in
                patch.changedRanges.contains { NSIntersectionRange(token.range, $0).length > 0 }
            }
            incrementalTokens.append(contentsOf: patch.tokens)
            #expect(incrementalTokens.count == Set(incrementalTokens).count)
            let expected = try await MarkdownHighlighter().tokens(for: source)
            #expect(TokenCanonicalization.canonical(incrementalTokens) == TokenCanonicalization.canonical(expected))
        }
    }

    // Validates: REQ-041, REQ-045 — deterministic generated edit sequences preserve the fresh-lexer
    // result across varied delimiter, fence, Unicode, and newline edits.
    @Test func generatedEditSequencesMatchFreshFullLexer() async throws {
        let fixtures = [
            "heading\nplain text\n",
            "~~open\nsecond line\n",
            "- item\n- **bold** and `code`\n",
            "🐙\n```swift\nlet value = 1\n```\n"
        ]
        let generatedLines = [
            "plain text\n", "~~open\n", "closed~~\n", "```swift\n", "let value = 1\n", "```\n", "🐳\n"
        ]

        for seed in [11, 29, 47, 83, 131] {
            var generator = DeterministicEditGenerator(seed: seed)
            var source = fixtures[generator.nextIndex(upperBound: fixtures.count)]
            let highlighter = IncrementalSourceHighlighter()
            var incrementalTokens = try await highlighter.highlight(
                source: source,
                editedRange: nil,
                sourceRevision: UInt64(seed),
                intentID: nil
            ).tokens

            for step in 0..<10 {
                let sourceNSString = source as NSString
                let lines = SourceLineIndex(source: source).lines
                let append = lines.count <= 1 || generator.nextIndex(upperBound: 2) == 0
                let edit: NSRange
                let replacement: String
                if append {
                    edit = NSRange(location: sourceNSString.length, length: 0)
                    replacement = generatedLines[generator.nextIndex(upperBound: generatedLines.count)]
                } else {
                    edit = lines[lines.count - 1]
                    replacement = ""
                }
                let mutable = NSMutableString(string: source)
                mutable.replaceCharacters(in: edit, with: replacement)
                source = mutable as String
                let changedRange = NSRange(location: edit.location, length: (replacement as NSString).length)
                let patch = try await highlighter.highlight(
                    source: source,
                    editedRange: changedRange,
                    sourceRevision: UInt64(seed * 100 + step + 1),
                    intentID: nil
                )
                incrementalTokens.removeAll { token in
                    NSMaxRange(token.range) > (source as NSString).length ||
                        patch.changedRanges.contains { NSIntersectionRange(token.range, $0).length > 0 }
                }
                incrementalTokens.append(contentsOf: patch.tokens)
                #expect(incrementalTokens.count == Set(incrementalTokens).count)
                let expected = try await MarkdownHighlighter().tokens(for: source)
                #expect(TokenCanonicalization.canonical(incrementalTokens) == TokenCanonicalization.canonical(expected), "seed=\(seed) step=\(step) source=\(source.debugDescription)")
            }
        }
    }

    // Validates: REQ-041 — same-line strikethrough tokens are emitted once even when the
    // cross-line state handler observes the same delimiter.
    @Test func sameLineStrikethroughDoesNotDuplicateTokens() async throws {
        let source = "~~closed~~\n"
        let patch = try await IncrementalSourceHighlighter().highlight(
            source: source,
            editedRange: nil,
            sourceRevision: 7,
            intentID: nil
        )
        #expect(patch.tokens.filter { $0.style == .strikethrough } == [
            Token(range: NSRange(location: 0, length: 10), style: .strikethrough)
        ])
    }

    private struct DeterministicEditGenerator {
        private var state: UInt64

        init(seed: Int) { state = UInt64(seed) }

        mutating func nextIndex(upperBound: Int) -> Int {
            precondition(upperBound > 0)
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return Int(state % UInt64(upperBound))
        }
    }


    // Validates: REQ-041, REQ-045 — COR-84 regression 1: an unclosed `[` must not pair with a `](` on a
    // later line. The full lexer's link-text class admitted a newline while every other inline rule
    // excluded it, so it emitted a token spanning a newline that a line-local incremental lexer
    // structurally cannot reproduce. Minimized by `Shrinker` from a 233-character generated
    // document to these two lines.
    @Test func unclosedBracketDoesNotPairAcrossALineBoundary() async throws {
        let source = "- [x\\*delta\\_\\`\n![x](assets/x.png) x *x*"
        let tokens = try await MarkdownHighlighter().tokens(for: source)
        let ns = source as NSString
        for token in tokens {
            let text = ns.substring(with: token.range)
            #expect(
                !text.contains("\n"),
                "\(token.style) spans a newline: \(NSStringFromRange(token.range)) = \(text.debugDescription)"
            )
        }
    }

    // Validates: REQ-041, REQ-045 — COR-84 regression 2: a cross-line strikethrough overlapping inline
    // code must be suppressed, because the whole-text lexer skips any strikethrough overlapping an
    // exclusive range. The incremental cross-line path bypassed that precedence and emitted a token
    // the full relex does not.
    @Test func crossLineStrikethroughOverlappingInlineCodeIsSuppressed() async throws {
        let source = "> ~~alpha~~ \\*beta\\_\\` gamma\n> ~~alpha~~ \\*beta\\_\\` gamma"
        let highlighter = IncrementalSourceHighlighter()
        _ = try await highlighter.highlight(source: source, editedRange: nil, sourceRevision: 1, intentID: nil)

        let ns = source as NSString
        let insertAt = ns.range(of: "~~alpha~~", options: .backwards).location + 7
        let mutable = NSMutableString(string: source)
        mutable.replaceCharacters(in: NSRange(location: insertAt, length: 0), with: "```")
        let edited = mutable as String

        let patch = try await highlighter.highlight(
            source: edited,
            editedRange: NSRange(location: insertAt, length: 3),
            sourceRevision: 2,
            intentID: nil
        )
        let full = try await MarkdownHighlighter().tokens(for: edited)

        for changed in patch.changedRanges {
            let incremental = TokenCanonicalization.canonical(TokenCanonicalization.clipped(patch.tokens, to: changed))
            let expected = TokenCanonicalization.canonical(TokenCanonicalization.clipped(full, to: changed))
            #expect(incremental == expected, "disagreement in \(NSStringFromRange(changed))")
        }
    }

}
