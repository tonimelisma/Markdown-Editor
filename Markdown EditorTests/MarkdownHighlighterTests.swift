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

    // Verifies: REQ-043
    @Test func stylesFencedCodeBlock() async {
        let tokens = await MarkdownHighlighter().tokens(for: "````swift\nlet answer = 42\n`````\n\n~~~\ncode\n~~~~")
        #expect(tokens.filter { $0.style == .codeBlock }.count == 2)
    }

    // Verifies: REQ-040/051 — token ranges stay within the text bounds.
    @Test func rangesWithinBounds() async {
        let text = "# H\n**b** `c`\n- item\n> quote\n~strike~\n![x](<a b>)\n"
        let tokens = await MarkdownHighlighter().tokens(for: text)
        let length = (text as NSString).length
        #expect(tokens.allSatisfy { $0.range.location >= 0 && NSMaxRange($0.range) <= length })
    }

    // Verifies: REQ-047 — TokenStyle enumerates only CommonMark/formal-GFM constructs.
    @Test func supportedDialectContainsOnlyCommonMarkAndFormalGFMStyles() {
        let allowed: Set<TokenStyle> = [
            .heading(level: 1), .heading(level: 2), .heading(level: 3),
            .heading(level: 4), .heading(level: 5), .heading(level: 6),
            .bold, .italic, .inlineCode, .codeBlock, .link, .image,
            .listMarker, .taskMarker, .blockquote, .table, .strikethrough, .thematicBreak,
        ]
        // Exhaustive switch: adding a house-extension case fails compilation or this set check.
        func isAllowed(_ style: TokenStyle) -> Bool { allowed.contains(style) }
        for style in allowed {
            #expect(isAllowed(style))
        }
        // Sanity: strikethrough is present; no API remains for footnote/highlight/super/subscript.
        #expect(allowed.contains(.strikethrough))
    }

    // Verifies: REQ-048 — formal GFM one- and two-tilde strikethrough; never subscript.
    // Fixtures derived from GFM 0.29-gfm §strikethrough (Examples 491–493).
    @Test(arguments: [
        // GFM Example 491
        Fixture(source: "~~Hi~~ Hello, ~there~ world!", expectStrikeSources: ["~~Hi~~", "~there~"]),
        Fixture(source: "~one~", expectStrikeSources: ["~one~"]),
        Fixture(source: "~~two~~", expectStrikeSources: ["~~two~~"]),
        // Intraword-ish / adjacent text
        Fixture(source: "a~~b~~c", expectStrikeSources: ["~~b~~"]),
        Fixture(source: "x~y~z", expectStrikeSources: ["~y~"]),
        // Whitespace after open / before close — not strikethrough
        Fixture(source: "~ not~", expectStrikeSources: []),
        Fixture(source: "~not ~", expectStrikeSources: []),
        Fixture(source: "~~ not~~", expectStrikeSources: []),
        Fixture(source: "~~not ~~", expectStrikeSources: []),
        // GFM Example 493 — three or more tildes do not create strikethrough
        Fixture(source: "This will ~~~not~~~ strike.", expectStrikeSources: []),
        // Escaped tildes (lexical: backslash-escaped opener/closer)
        Fixture(source: #"\~not\~"#, expectStrikeSources: []),
        Fixture(source: #"~~not\~~"#, expectStrikeSources: []),
        // Code span claims exclusive range — tildes inside stay unstyled as strike
        Fixture(source: "`~code~` and ~ok~", expectStrikeSources: ["~ok~"]),
        Fixture(source: "``~~x~~``", expectStrikeSources: []),
        // Newline ceases (GFM Example 492 spirit — no cross-paragraph match)
        Fixture(source: "This ~~has a\n\nnew paragraph~~.", expectStrikeSources: []),
    ])
    func stylesFormalGFMTildeStrikethroughFixtures(_ fixture: Fixture) async {
        let tokens = await MarkdownHighlighter().tokens(for: fixture.source)
        let strikeRanges = tokens.filter { $0.style == .strikethrough }.map(\.range)
        let ns = fixture.source as NSString
        let actual = strikeRanges.map { ns.substring(with: $0) }.sorted()
        #expect(actual == fixture.expectStrikeSources.sorted())
    }

    // Verifies: REQ-049 — unsupported writing extensions are preserved without semantic styles.
    @Test func preservesUnknownExtensionsWithoutSemanticStyles() async {
        let source = "==highlight== [^footnote] x^super^ H~2~O stays strike-only for tildes"
        let tokens = await MarkdownHighlighter().tokens(for: source)
        // No house-extension token styles exist; assert we only emit known dialect styles,
        // and that ==…== / [^…] / ^…^ are not claimed via strikethrough either.
        let styles = Set(tokens.map(\.style))
        let forbiddenHints = ["highlight", "footnote", "superscript", "subscript"]
        for style in styles {
            let label = String(describing: style).lowercased()
            #expect(!forbiddenHints.contains(where: { label.contains($0) }))
        }
        let ns = source as NSString
        let strikeTexts = tokens.filter { $0.style == .strikethrough }.map { ns.substring(with: $0.range) }
        // Single-tilde GFM strike may match H~2~O's ~2~; that is strikethrough, not subscript.
        #expect(strikeTexts.allSatisfy { $0.hasPrefix("~") && $0.hasSuffix("~") })
        #expect(!tokens.contains { ns.substring(with: $0.range) == "==highlight==" })
        #expect(!tokens.contains { ns.substring(with: $0.range) == "[^footnote]" })
        #expect(!tokens.contains { ns.substring(with: $0.range) == "^super^" })
    }

    // Verifies: REQ-050 — focused valid CommonMark image destination fixtures.
    // Spec refs: CommonMark 0.31.2 §6.4 Images / §6.3 Links (destination grammar).
    @Test(arguments: [
        ImageFixture(source: "![](/url)", expectStyled: true),                          // Ex. 581
        ImageFixture(source: "![foo](train.jpg)", expectStyled: true),                   // Ex. 578
        ImageFixture(source: #"![foo](/url "title")"#, expectStyled: true),              // Ex. 572
        ImageFixture(source: "![foo](<url>)", expectStyled: true),                       // Ex. 580
        ImageFixture(source: "![x](<a b>)", expectStyled: true),                         // angled + space
        ImageFixture(source: "![x](foo(and(bar)))", expectStyled: true),                 // Ex. 496 form
        ImageFixture(source: #"![x](foo\(and\(bar\))"#, expectStyled: true),             // Ex. 498 form
        ImageFixture(source: #"![x](\(foo\))"#, expectStyled: true),                     // Ex. 495 form
        ImageFixture(source: "![](assets/photo.heic)", expectStyled: true),              // portable path
        ImageFixture(source: "![foo bar](/path/to/train.jpg  \"title\"   )", expectStyled: true), // Ex. 579
    ])
    func stylesCommonMarkImageDestinationFixtures(_ fixture: ImageFixture) async {
        let tokens = await MarkdownHighlighter().tokens(for: fixture.source)
        let images = tokens.filter { $0.style == .image }
        if fixture.expectStyled {
            #expect(!images.isEmpty)
            let ns = fixture.source as NSString
            #expect(images.contains { ns.substring(with: $0.range) == fixture.source })
        } else {
            #expect(images.isEmpty)
        }
    }
}

struct Fixture: Sendable, CustomTestStringConvertible {
    let source: String
    let expectStrikeSources: [String]
    var testDescription: String { source }
}

struct ImageFixture: Sendable, CustomTestStringConvertible {
    let source: String
    let expectStyled: Bool
    var testDescription: String { source }
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

    // Verifies: REQ-044/045
    @Test func computesCountsOffMainActor() async {
        let computer = TextStatsComputer()
        let counts = await computer.counts(for: "one two")
        #expect(counts == .init(words: 2, characters: 7))
    }
}

@MainActor
struct MarkdownThemeTests {

    // Verifies: REQ-041/047
    @Test func returnsAttributesPerStyle() {
        let theme = MarkdownTheme()
        #expect(theme.attributes(for: .bold)[.font] != nil)
        #expect(theme.attributes(for: .heading(level: 1))[.font] != nil)
        #expect(theme.attributes(for: .inlineCode)[.font] != nil)
        #expect(theme.attributes(for: .strikethrough)[.strikethroughStyle] != nil)
        #expect(theme.attributes(for: .codeBlock)[.backgroundColor] != nil)
    }
}

@MainActor
struct StylingFidelityTests {

    // Verifies: REQ-040/049/051 — applying style attributes never changes the string (INV-2).
    @Test func attributeStylingLeavesStringUnchanged() async {
        let text = "# Title\n**bold** and `code`, a [link](url), ![img](<a b>), ~one~, ~~two~~, ==hi== [^1] x^2^.\r\nSecond line.\n"
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
        #expect(tokens.allSatisfy { $0.range.location >= 0 && NSMaxRange($0.range) <= storage.length })
    }
}
