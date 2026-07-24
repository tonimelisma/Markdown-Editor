//
//  MarkdownHighlighter.swift
//  Markdown Editor
//

import Foundation

// REQ-041/043/047–051: compute style tokens for Markdown source via regex (ADR-0009),
// off the main actor (ADR-0010). Patterns are compiled once. Regex is lexical, so some
// nested/pathological constructs are approximate — an accepted limit per ADR-0009.
// Supported dialect labels are CommonMark 0.31.2 + formal GFM 0.29-gfm only (ADR-0003).
actor MarkdownHighlighter {
    private struct Rule {
        let regex: NSRegularExpression
        let style: TokenStyle
        /// When true, matches that overlap an exclusive (code) range are skipped.
        let skipIfExclusiveCovered: Bool
    }

    private let headingRegex: NSRegularExpression
    private let exclusiveRules: [Rule]
    private let rules: [Rule]

    init() {
        func re(_ pattern: String) -> NSRegularExpression {
            // Patterns are compile-time constants; a failure here is a programmer error.
            try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }
        headingRegex = re(#"^(#{1,6})[ \t]+\S.*$"#)

        // Code spans/blocks claim exclusive ranges so tilde strikethrough and other inline
        // styles do not paint inside them (REQ-048 / REQ-051 fixtures).
        exclusiveRules = [
            Rule(regex: re(#"(?m)^`{3,}[^\n]*\n[\s\S]*?^`{3,}[ \t]*$"#), style: .codeBlock, skipIfExclusiveCovered: false),
            Rule(regex: re(#"(?m)^~{3,}[^\n]*\n[\s\S]*?^~{3,}[ \t]*$"#), style: .codeBlock, skipIfExclusiveCovered: false),
            Rule(regex: re(#"`[^`\n]+`"#), style: .inlineCode, skipIfExclusiveCovered: false),
        ]

        // Image: focused CommonMark destination forms — angled `<…>`, optional title,
        // backslash escapes, and up to one nested level of balanced parentheses (REQ-050).
        // Not a complete nested-grammar parser.
        let imagePattern = #"""
        !\[[^\]]*\]\(\s*(?:<[^>\n]*>|(?:[^()\s\\]|\\.|(\((?:[^()\s\\]|\\.|\([^()\s\\]*\))*\)))+)(?:\s+(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\((?:[^)\\]|\\.)*\)))?\s*\)
        """#.trimmingCharacters(in: .whitespacesAndNewlines)

        // Formal GFM strikethrough (0.29-gfm §strikethrough): matching one or two tildes;
        // open not followed by whitespace; close not preceded by whitespace; three-or-more
        // runs are not strikethrough (REQ-048). Never subscript.
        let doubleStrike = #"(?<![~\\])~~(?!~)(?!\s)(?:(?!~~)[^\n])*?(?<!\s)(?<!\\)~~(?!~)"#
        let singleStrike = #"(?<![~\\])~(?!~)(?!\s)(?:(?!~)[^\n])*?(?<!\s)(?<!\\)~(?!~)"#

        rules = [
            Rule(regex: re(imagePattern), style: .image, skipIfExclusiveCovered: true),
            Rule(regex: re(#"\[[^\]]*\]\([^)\s]*\)"#), style: .link, skipIfExclusiveCovered: true),
            Rule(regex: re(#"\*\*[^\n]+?\*\*"#), style: .bold, skipIfExclusiveCovered: true),
            Rule(regex: re(#"__[^\n]+?__"#), style: .bold, skipIfExclusiveCovered: true),
            Rule(regex: re(#"(?<![*\w])\*(?!\*)[^\n*]+?\*(?!\*)"#), style: .italic, skipIfExclusiveCovered: true),
            Rule(regex: re(#"(?<![_\w])_(?!_)[^\n_]+?_(?!_)"#), style: .italic, skipIfExclusiveCovered: true),
            Rule(regex: re(doubleStrike), style: .strikethrough, skipIfExclusiveCovered: true),
            Rule(regex: re(singleStrike), style: .strikethrough, skipIfExclusiveCovered: true),
            Rule(regex: re(#"^[ \t]*>.*$"#), style: .blockquote, skipIfExclusiveCovered: true),
            Rule(regex: re(#"^[ \t]*[-*+][ \t]+\[[ xX]\]"#), style: .taskMarker, skipIfExclusiveCovered: true),
            Rule(regex: re(#"^[ \t]*([-*+]|\d+[.)])[ \t]+"#), style: .listMarker, skipIfExclusiveCovered: true),
            Rule(regex: re(#"^[ \t]*[|].*[|][ \t]*$"#), style: .table, skipIfExclusiveCovered: true),
            Rule(regex: re(#"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#), style: .thematicBreak, skipIfExclusiveCovered: true),
        ]
    }

    // REQ-040/051: pure function — takes the text by value, returns styled ranges. Never mutates text.
    func tokens(for text: String) -> [Token] {
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)
        var result: [Token] = []
        var exclusiveRanges: [NSRange] = []

        headingRegex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match else { return }
            let level = match.range(at: 1).length
            result.append(Token(range: match.range, style: .heading(level: min(max(level, 1), 6))))
        }

        for rule in exclusiveRules {
            rule.regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                guard let match else { return }
                result.append(Token(range: match.range, style: rule.style))
                exclusiveRanges.append(match.range)
            }
        }

        for rule in rules {
            rule.regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                guard let match else { return }
                if rule.skipIfExclusiveCovered, Self.overlapsAny(match.range, exclusiveRanges) {
                    return
                }
                result.append(Token(range: match.range, style: rule.style))
            }
        }
        return result
    }

    private static func overlapsAny(_ range: NSRange, _ others: [NSRange]) -> Bool {
        others.contains { NSIntersectionRange(range, $0).length > 0 }
    }
}
