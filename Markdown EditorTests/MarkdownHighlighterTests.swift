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
    @Test func stylesHeadingWithLevel() async throws {
        let tokens = try await MarkdownHighlighter().tokens(for: "## Title\n")
        #expect(tokens.contains {
            if case .heading(let level) = $0.style { return level == 2 }
            return false
        })
    }

    // Verifies: REQ-041
    @Test func stylesInlineElements() async throws {
        let tokens = try await MarkdownHighlighter().tokens(for: "**b** *i* _also italic_ `c` [a](b) ![x](y)")
        #expect(tokens.contains { $0.style == .bold })
        #expect(tokens.contains { $0.style == .italic })
        #expect(tokens.contains { $0.style == .inlineCode })
        #expect(tokens.contains { $0.style == .link })
        #expect(tokens.contains { $0.style == .image })
    }

    // Verifies: REQ-043
    @Test func stylesFencedCodeBlock() async throws {
        let tokens = try await MarkdownHighlighter().tokens(for: "````swift\nlet answer = 42\n`````\n\n~~~\ncode\n~~~~")
        #expect(tokens.filter { $0.style == .codeBlock }.count == 2)
    }

    // Verifies: REQ-041/043 — closer shorter than opener does not close; content stays fenced.
    @Test func rejectsShorterFenceCloser() async throws {
        let source = "````\n~~inside~~\n```\nstill code\n````\n"
        let tokens = try await MarkdownHighlighter().tokens(for: source)
        #expect(tokens.contains { $0.style == .codeBlock })
        #expect(!tokens.contains { $0.style == .strikethrough })
    }

    // Verifies: REQ-041/043 — indent ≤3 and unclosed fence → EOF; no strike inside.
    @Test func indentedAndUnclosedFenceExcludesInlineStyles() async throws {
        let indented = "   ~~~\n~~inside~~\n~~~\n"
        let indentedTokens = try await MarkdownHighlighter().tokens(for: indented)
        #expect(indentedTokens.contains { $0.style == .codeBlock })
        #expect(!indentedTokens.contains { $0.style == .strikethrough })

        let unclosed = "~~~\n~~inside~~\n"
        let unclosedTokens = try await MarkdownHighlighter().tokens(for: unclosed)
        #expect(unclosedTokens.contains { $0.style == .codeBlock })
        #expect(!unclosedTokens.contains { $0.style == .strikethrough })
    }

    // Verifies: REQ-040/051 — token ranges stay within the text bounds.
    @Test func rangesWithinBounds() async throws {
        let text = "# H\n**b** `c`\n- item\n> quote\n~strike~\n![x](<a b>)\n"
        let tokens = try await MarkdownHighlighter().tokens(for: text)
        let length = (text as NSString).length
        #expect(tokens.allSatisfy { $0.range.location >= 0 && NSMaxRange($0.range) <= length })
    }

    // Verifies: REQ-047 — exhaustive switch over TokenStyle; a new house-extension case fails to compile.
    @Test func supportedDialectContainsOnlyCommonMarkAndFormalGFMStyles() {
        let samples: [TokenStyle] = [
            .heading(level: 1), .heading(level: 2), .heading(level: 3),
            .heading(level: 4), .heading(level: 5), .heading(level: 6),
            .bold, .italic, .inlineCode, .codeBlock, .link, .image,
            .listMarker, .taskMarker, .blockquote, .table, .strikethrough, .thematicBreak,
        ]
        for style in samples {
            #expect(Self.isCommonMarkOrFormalGFM(style))
        }
    }

    /// Compile-time-complete mapping: adding a case to `TokenStyle` forces an edit here.
    private static func isCommonMarkOrFormalGFM(_ style: TokenStyle) -> Bool {
        switch style {
        case .heading, .bold, .italic, .inlineCode, .codeBlock, .link, .image,
             .listMarker, .taskMarker, .blockquote, .table, .strikethrough, .thematicBreak:
            return true
        }
    }

    // Verifies: REQ-048 — formal GFM one- and two-tilde strikethrough; never subscript.
    // Fixtures derived from GFM 0.29-gfm §strikethrough (Examples 491–493) plus soft-break /
    // escape-parity cases required for Done status.
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
        // Soft line break permitted; blank line (new paragraph) terminates (GFM Ex. 492).
        Fixture(source: "~~soft\nline~~", expectStrikeSources: ["~~soft\nline~~"]),
        Fixture(source: "This ~~has a\n\nnew paragraph~~.", expectStrikeSources: []),
        // Escape parity: odd backslashes escape; even do not. Delimiter runs are atomic.
        Fixture(source: #"\~not\~"#, expectStrikeSources: []),
        Fixture(source: #"\\~~even~~"#, expectStrikeSources: ["~~even~~"]),
        Fixture(source: #"\~~Hi~~"#, expectStrikeSources: []),
        Fixture(source: #"~~not\~~"#, expectStrikeSources: []),
        // Code span / fence exclusivity
        Fixture(source: "`~code~` and ~ok~", expectStrikeSources: ["~ok~"]),
        Fixture(source: "``~~x~~``", expectStrikeSources: []),
        Fixture(source: "~~~\n~~inside~~\n~~~\n", expectStrikeSources: []),
        Fixture(source: "```\n~~inside~~\n```\n", expectStrikeSources: []),
    ])
    func stylesFormalGFMTildeStrikethroughFixtures(_ fixture: Fixture) async throws {
        let tokens = try await MarkdownHighlighter().tokens(for: fixture.source)
        let strikeRanges = tokens.filter { $0.style == .strikethrough }.map(\.range)
        let ns = fixture.source as NSString
        let actual = strikeRanges.map { ns.substring(with: $0) }.sorted()
        #expect(actual == fixture.expectStrikeSources.sorted())
    }

    // Verifies: REQ-049 — unsupported writing extensions are preserved without semantic styles.
    @Test func preservesUnknownExtensionsWithoutSemanticStyles() async throws {
        let source = "==highlight== [^footnote] x^super^ H~2~O stays strike-only for tildes"
        let tokens = try await MarkdownHighlighter().tokens(for: source)
        let styles = Set(tokens.map(\.style))
        for style in styles {
            #expect(Self.isCommonMarkOrFormalGFM(style))
        }
        let ns = source as NSString
        let strikeTexts = tokens.filter { $0.style == .strikethrough }.map { ns.substring(with: $0.range) }
        #expect(strikeTexts.allSatisfy { $0.hasPrefix("~") && $0.hasSuffix("~") })
        #expect(!tokens.contains { ns.substring(with: $0.range) == "==highlight==" })
        #expect(!tokens.contains { ns.substring(with: $0.range) == "[^footnote]" })
        #expect(!tokens.contains { ns.substring(with: $0.range) == "^super^" })
    }

    // Verifies: REQ-050 — focused valid CommonMark image destination fixtures (+ negatives).
    @Test(arguments: [
        ImageFixture(source: "![](/url)", expectStyled: true),
        ImageFixture(source: "![foo](train.jpg)", expectStyled: true),
        ImageFixture(source: #"![foo](/url "title")"#, expectStyled: true),
        ImageFixture(source: "![foo](<url>)", expectStyled: true),
        ImageFixture(source: "![x](<a b>)", expectStyled: true),
        ImageFixture(source: "![x](foo(and(bar)))", expectStyled: true),
        ImageFixture(source: #"![x](foo\(and\(bar\))"#, expectStyled: true),
        ImageFixture(source: #"![x](\(foo\))"#, expectStyled: true),
        ImageFixture(source: "![](assets/photo.heic)", expectStyled: true),
        ImageFixture(source: "![foo bar](/path/to/train.jpg  \"title\"   )", expectStyled: true),
        // Negatives — outside the focused lexical claim
        ImageFixture(source: "![x](a b)", expectStyled: false),                 // unangled space
        ImageFixture(source: "![x](foo(and(bar(baz))))", expectStyled: false), // deeper nesting
    ])
    func stylesCommonMarkImageDestinationFixtures(_ fixture: ImageFixture) async throws {
        let tokens = try await MarkdownHighlighter().tokens(for: fixture.source)
        let images = tokens.filter { $0.style == .image }
        if fixture.expectStyled {
            #expect(!images.isEmpty)
            let ns = fixture.source as NSString
            #expect(images.contains { ns.substring(with: $0.range) == fixture.source })
        } else {
            #expect(images.isEmpty)
        }
    }

    // Verifies: REQ-041 — GFM tables without edge pipes are styled.
    @Test func stylesTablesWithoutEdgePipes() async throws {
        let tokens = try await MarkdownHighlighter().tokens(for: "a | b\n--- | ---\n")
        #expect(tokens.contains { $0.style == .table })
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
        // Exhaustive: every TokenStyle must produce attributes (compile-fails on new cases).
        let styles: [TokenStyle] = [
            .heading(level: 1), .bold, .italic, .inlineCode, .codeBlock, .link, .image,
            .listMarker, .taskMarker, .blockquote, .table, .strikethrough, .thematicBreak,
        ]
        for style in styles {
            switch style {
            case .heading, .bold, .italic, .inlineCode, .codeBlock, .link, .image,
                 .listMarker, .taskMarker, .blockquote, .table, .strikethrough, .thematicBreak:
                #expect(!theme.attributes(for: style).isEmpty)
            }
        }
    }
}

@MainActor
struct StylingFidelityTests {

    // Verifies: REQ-040/049/051 — applying style attributes never changes the string (INV-2).
    @Test func attributeStylingLeavesStringUnchanged() async throws {
        let text = "# Title\n**bold** and `code`, a [link](url), ![img](<a b>), ~one~, ~~two~~, ==hi== [^1] x^2^.\r\nSecond line.\n"
        let storage = NSTextStorage(string: text)
        let theme = MarkdownTheme()
        let tokens = try await MarkdownHighlighter().tokens(for: text)
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
