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
}
