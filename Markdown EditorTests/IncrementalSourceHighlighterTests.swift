//
//  IncrementalSourceHighlighterTests.swift
//  Markdown EditorTests
//

import Foundation
import Testing
@testable import Markdown_Editor

struct IncrementalSourceHighlighterTests {
    // Verifies: REQ-040/041/043 — the line lexer carries a fence state and does not style code
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

    // Verifies: REQ-045 — a local paragraph edit stops after the incoming/outgoing lexical state
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

    // Verifies: REQ-040/045 — CRLF and Unicode remain UTF-16 bounded across line patches.
    @Test func lineRangesRemainUTF16ExactForCRLFAndUnicode() async throws {
        let source = "🐙 **one**\r\nsecond\r\n"
        let highlighter = IncrementalSourceHighlighter()
        let patch = try await highlighter.highlight(source: source, editedRange: nil, sourceRevision: 3, intentID: nil)
        let length = (source as NSString).length
        #expect(patch.changedRanges.allSatisfy { $0.location >= 0 && NSMaxRange($0) <= length })
        #expect(patch.tokens.allSatisfy { $0.range.location >= 0 && NSMaxRange($0.range) <= length })
        #expect(SourceLineIndex(source: source).lines.map(\.length) == [12, 8])
    }

    // Verifies: REQ-040/045 — an edit that grows a terminal newline uses the topology fallback
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

    // Verifies: REQ-041/043 — multiline GFM strikethrough state crosses a soft line break and
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

    // Verifies: REQ-041 — escaped and unmatched tilde runs remain literal, while a later
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

    // Verifies: REQ-041/045 — a sequence of edits has the same token result as a fresh full
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
            let expected = try await MarkdownHighlighter().tokens(for: source)
            #expect(canonicalTokens(incrementalTokens) == canonicalTokens(expected))
        }
    }

    private func canonicalTokens(_ tokens: [Token]) -> [Token] {
        let sorted = tokens.sorted(by: tokenOrder)
        return sorted.reduce(into: [Token]()) { result, token in
            guard let previous = result.last else {
                result.append(token)
                return
            }
            if previous.style == token.style, NSMaxRange(previous.range) >= token.range.location {
                result[result.count - 1] = Token(
                    range: NSUnionRange(previous.range, token.range),
                    style: previous.style
                )
            } else {
                result.append(token)
            }
        }
    }

    private func tokenOrder(_ lhs: Token, _ rhs: Token) -> Bool {
        if lhs.range.location != rhs.range.location { return lhs.range.location < rhs.range.location }
        if lhs.range.length != rhs.range.length { return lhs.range.length < rhs.range.length }
        return String(describing: lhs.style) < String(describing: rhs.style)
    }
}
