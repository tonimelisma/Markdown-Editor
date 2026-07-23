//
//  MarkdownHighlighterTests.swift
//  Markdown EditorTests
//

import Testing
import Foundation
import AppKit
@testable import Markdown_Editor

struct MarkdownHighlighterTests {

    // Verifies: REQ-041
    @Test func stylesHeadingWithLevel() async {
        let tokens = await MarkdownHighlighter().tokens(for: "## Title\n")
        #expect(tokens.contains {
            if case .heading(let level) = $0.style { return level == 2 }
            return false
        })
    }

    // Verifies: REQ-041
    @Test func stylesInlineElements() async {
        let tokens = await MarkdownHighlighter().tokens(for: "**b** *i* _also italic_ `c` [a](b) ![x](y)")
        #expect(tokens.contains { $0.style == .bold })
        #expect(tokens.contains { $0.style == .italic })
        #expect(tokens.contains { $0.style == .inlineCode })
        #expect(tokens.contains { $0.style == .link })
        #expect(tokens.contains { $0.style == .image })
    }

    // Verifies: REQ-042
    @Test func stylesLightTier2() async {
        let tokens = await MarkdownHighlighter().tokens(for: "==hi== [^1] ~~s~~ x^2^")
        #expect(tokens.contains { $0.style == .highlight })
        #expect(tokens.contains { $0.style == .footnote })
        #expect(tokens.contains { $0.style == .strikethrough })
        #expect(tokens.contains { $0.style == .superscript })
    }

    // Verifies: REQ-043
    @Test func stylesFencedCodeBlock() async {
        let tokens = await MarkdownHighlighter().tokens(for: "````swift\nlet answer = 42\n`````\n\n~~~\ncode\n~~~~")
        #expect(tokens.filter { $0.style == .codeBlock }.count == 2)
    }

    // Verifies: REQ-040 — token ranges stay within the text bounds.
    @Test func rangesWithinBounds() async {
        let text = "# H\n**b** `c`\n- item\n> quote\n"
        let tokens = await MarkdownHighlighter().tokens(for: text)
        let length = (text as NSString).length
        #expect(tokens.allSatisfy { $0.range.location >= 0 && NSMaxRange($0.range) <= length })
    }
}

struct TextStatsTests {

    // Verifies: REQ-044
    @Test func countsWordsAndCharacters() {
        #expect(TextStats.wordCount("the quick brown fox") == 4)
        #expect(TextStats.wordCount("  spaced \n out \t words ") == 3)
        #expect(TextStats.wordCount("") == 0)
        #expect(TextStats.characterCount("abc") == 3)
        #expect(TextStats.counts("one two") == .init(words: 2, characters: 7))
    }
}

@MainActor
struct MarkdownThemeTests {

    // Verifies: REQ-041
    @Test func returnsAttributesPerStyle() {
        let theme = MarkdownTheme()
        #expect(theme.attributes(for: .bold)[.font] != nil)
        #expect(theme.attributes(for: .heading(level: 1))[.font] != nil)
        #expect(theme.attributes(for: .inlineCode)[.font] != nil)
        #expect(theme.attributes(for: .highlight)[.backgroundColor] != nil)
        #expect(theme.attributes(for: .codeBlock)[.backgroundColor] != nil)
    }
}

@MainActor
struct StylingFidelityTests {

    // Verifies: REQ-040 — applying style attributes never changes the string (INV-2).
    @Test func attributeStylingLeavesStringUnchanged() async {
        let text = "# Title\n**bold** and `code`, a [link](url).\r\nSecond line.\n"
        let storage = NSTextStorage(string: text)
        let theme = MarkdownTheme()
        let tokens = await MarkdownHighlighter().tokens(for: text)
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(theme.baseAttributes, range: full)
        for token in tokens where NSMaxRange(token.range) <= storage.length {
            storage.addAttributes(theme.attributes(for: token.style), range: token.range)
        }
        storage.endEditing()
        #expect(storage.string == text)
    }
}
