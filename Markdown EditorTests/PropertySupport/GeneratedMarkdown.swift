//
//  GeneratedMarkdown.swift
//  Markdown EditorTests
//

import Foundation

/// Closed generator dimensions. These are enumerations rather than a hand-picked list of strings so
/// that adding a construct to the product fails the dimension-coverage assertion until the
/// generator knows how to produce it.
///
/// // REQ-132: "enumerate every declared input dimension". A generator that emits whatever the
/// // author thought of is variety, not coverage.
enum BlockKind: CaseIterable {
    case paragraph
    case atxHeading
    case setextHeading
    case bulletList
    case orderedList
    case taskList
    case blockQuote
    case fencedCode
    case indentedCode
    case table
    case thematicBreak
    case htmlBlock
    case blankRun
}

enum InlineKind: CaseIterable {
    case plain
    case emphasis
    case strong
    case code
    case strikethrough
    case link
    case image
    case autolink
    case escapedPunctuation
    case entity
}

enum LineEnding: String, CaseIterable {
    case lf = "\n"
    case crlf = "\r\n"
}

enum TextFlavor: CaseIterable {
    case ascii
    case latin1Supplement
    case cjk
    case emojiWithZWJ
    case combiningMarks
    case rightToLeft
}

enum Wellformedness: CaseIterable {
    case valid
    case malformed
}

/// One generated document plus the coordinates it was generated from, so a failure prints
/// everything needed to reproduce it without re-running the generator.
struct GeneratedDocument {
    let text: String
    let seed: UInt64
    let blocks: [BlockKind]
    let inlines: [InlineKind]
    let lineEnding: LineEnding
    let flavor: TextFlavor
    let wellformedness: Wellformedness
    let hasBOM: Bool

    var replayDescription: String {
        """
        seed=\(seed) lineEnding=\(lineEnding == .lf ? "LF" : "CRLF") flavor=\(flavor) \
        wellformed=\(wellformedness) bom=\(hasBOM)
        blocks=\(blocks) inlines=\(inlines)
        --- source (\(text.utf16.count) UTF-16 units) ---
        \(text.debugDescription)
        """
    }
}

enum GeneratedMarkdown {
    static func sample(for flavor: TextFlavor, rng: inout DeterministicRNG) -> String {
        switch flavor {
        case .ascii:
            return rng.pick(["alpha", "bravo charlie", "delta", "the quick brown fox"])
        case .latin1Supplement:
            return rng.pick(["café", "naïve résumé", "Grüße", "ñandú"])
        case .cjk:
            return rng.pick(["日本語のテキスト", "中文内容", "한국어 문장"])
        case .emojiWithZWJ:
            // Family and flag sequences: multi-scalar graphemes that break naive UTF-16 slicing.
            return rng.pick(["👨‍👩‍👧‍👦 family", "🇫🇮 flag", "👍🏽 thumb", "🧑‍💻 dev"])
        case .combiningMarks:
            return rng.pick(["e\u{0301}cole", "a\u{0308}bc", "n\u{0303}u"])
        case .rightToLeft:
            return rng.pick(["مرحبا بالعالم", "שלום עולם"])
        }
    }

    static func inline(_ kind: InlineKind, flavor: TextFlavor, rng: inout DeterministicRNG) -> String {
        let body = sample(for: flavor, rng: &rng)
        switch kind {
        case .plain: return body
        case .emphasis: return "*\(body)*"
        case .strong: return "**\(body)**"
        case .code: return "`\(body)`"
        case .strikethrough: return "~~\(body)~~"
        case .link: return "[\(body)](https://example.invalid/a)"
        case .image: return "![\(body)](assets/x.png)"
        case .autolink: return "<https://example.invalid/b>"
        case .escapedPunctuation: return "\\*\(body)\\_\\`"
        case .entity: return "\(body) &amp; &#65;"
        }
    }

    static func block(
        _ kind: BlockKind,
        inlines: [InlineKind],
        flavor: TextFlavor,
        wellformedness: Wellformedness,
        rng: inout DeterministicRNG
    ) -> [String] {
        var inlineRNG = rng
        let content = inlines.map { inline($0, flavor: flavor, rng: &inlineRNG) }.joined(separator: " ")
        rng = inlineRNG
        let malformed = wellformedness == .malformed

        switch kind {
        case .paragraph:
            return [content]
        case .atxHeading:
            let level = rng.next(below: 6) + 1
            return [malformed ? "\(String(repeating: "#", count: 7))\(content)"
                              : "\(String(repeating: "#", count: level)) \(content)"]
        case .setextHeading:
            return [content, malformed ? "=-=" : rng.bool() ? "===" : "---"]
        case .bulletList:
            return [rng.pick(["- ", "* ", "+ "]) + content, "- " + content]
        case .orderedList:
            return malformed ? ["1 \(content)", "2. \(content)"] : ["1. \(content)", "2. \(content)"]
        case .taskList:
            return malformed ? ["- [x\(content)"] : ["- [ ] \(content)", "- [x] \(content)"]
        case .blockQuote:
            return ["> " + content, malformed ? ">" : "> " + content]
        case .fencedCode:
            // The malformed case is an unterminated fence, which is exactly the state COR-72's
            // incremental lexer has to carry across lines.
            return malformed ? ["```swift", "let x = \(content)"]
                             : ["```swift", "let x = \(content)", "```"]
        case .indentedCode:
            return ["    indented \(content)"]
        case .table:
            return malformed
                ? ["| a | b |", "| --- |", "| 1 | 2 |"]
                : ["| a | b |", "| --- | --- |", "| \(content) | 2 |"]
        case .thematicBreak:
            return [rng.pick(["---", "***", "___"])]
        case .htmlBlock:
            return malformed ? ["<div class=\"x\">"] : ["<div class=\"x\">", "\(content)", "</div>"]
        case .blankRun:
            return ["", ""]
        }
    }

    /// Generates a document covering the given dimension coordinates.
    static func document(
        seed: UInt64,
        blockCount: Int = 6,
        lineEnding: LineEnding,
        flavor: TextFlavor,
        wellformedness: Wellformedness,
        hasBOM: Bool
    ) -> GeneratedDocument {
        var rng = DeterministicRNG(seed: seed)
        var chosenBlocks: [BlockKind] = []
        var chosenInlines: [InlineKind] = []
        var lines: [String] = []

        for _ in 0..<blockCount {
            let kind = rng.pick(BlockKind.allCases)
            let inlineCount = rng.next(below: 3) + 1
            let inlines = (0..<inlineCount).map { _ in rng.pick(InlineKind.allCases) }
            chosenBlocks.append(kind)
            chosenInlines.append(contentsOf: inlines)
            lines.append(contentsOf: block(
                kind,
                inlines: inlines,
                flavor: flavor,
                wellformedness: wellformedness,
                rng: &rng
            ))
            lines.append("")
        }

        var text = lines.joined(separator: lineEnding.rawValue) + lineEnding.rawValue
        if hasBOM { text = "\u{FEFF}" + text }

        return GeneratedDocument(
            text: text,
            seed: seed,
            blocks: chosenBlocks,
            inlines: chosenInlines,
            lineEnding: lineEnding,
            flavor: flavor,
            wellformedness: wellformedness,
            hasBOM: hasBOM
        )
    }

    /// The declared corpus: the full cross-product of the coarse dimensions, with `seedsPerCell`
    /// documents per cell. Fixed seeds, so a green run stays green and a red one replays.
    static func corpus(seedsPerCell: Int = 2) -> [GeneratedDocument] {
        var documents: [GeneratedDocument] = []
        var seed: UInt64 = 0x5EED
        for lineEnding in LineEnding.allCases {
            for flavor in TextFlavor.allCases {
                for wellformedness in Wellformedness.allCases {
                    for bom in [false, true] {
                        for _ in 0..<seedsPerCell {
                            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                            documents.append(document(
                                seed: seed,
                                lineEnding: lineEnding,
                                flavor: flavor,
                                wellformedness: wellformedness,
                                hasBOM: bom
                            ))
                        }
                    }
                }
            }
        }
        return documents
    }
}
