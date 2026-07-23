//
//  MarkdownHighlighter.swift
//  Markdown Editor
//

import Foundation

// REQ-041/042/043: compute style tokens for Markdown source via regex (ADR-0009),
// off the main actor (ADR-0010). Patterns are compiled once. Regex is lexical, so some
// nested/pathological constructs are approximate — an accepted limit per ADR-0009.
actor MarkdownHighlighter {
    private struct Rule {
        let regex: NSRegularExpression
        let style: TokenStyle
    }

    private let headingRegex: NSRegularExpression
    private let rules: [Rule]

    init() {
        func re(_ pattern: String) -> NSRegularExpression {
            // Patterns are compile-time constants; a failure here is a programmer error.
            try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }
        headingRegex = re(#"^(#{1,6})[ \t]+\S.*$"#)
        rules = [
            Rule(regex: re(#"(?m)^`{3,}[^\n]*\n[\s\S]*?^`{3,}[ \t]*$"#), style: .codeBlock),
            Rule(regex: re(#"(?m)^~{3,}[^\n]*\n[\s\S]*?^~{3,}[ \t]*$"#), style: .codeBlock),
            Rule(regex: re(#"`[^`\n]+`"#), style: .inlineCode),
            Rule(regex: re(#"!\[[^\]]*\]\([^)\s]*\)"#), style: .image),
            Rule(regex: re(#"\[[^\]]*\]\([^)\s]*\)"#), style: .link),
            Rule(regex: re(#"\*\*[^\n]+?\*\*"#), style: .bold),
            Rule(regex: re(#"__[^\n]+?__"#), style: .bold),
            Rule(regex: re(#"(?<![*\w])\*(?!\*)[^\n*]+?\*(?!\*)"#), style: .italic),
            Rule(regex: re(#"(?<![_\w])_(?!_)[^\n_]+?_(?!_)"#), style: .italic),
            Rule(regex: re(#"~~[^\n]+?~~"#), style: .strikethrough),
            Rule(regex: re(#"(?<![~\w])~(?!~)[^~\s\n]+?~(?!~)"#), style: .subscriptStyle),
            Rule(regex: re(#"==[^\n]+?=="#), style: .highlight),
            Rule(regex: re(#"\^[^\s^]+?\^"#), style: .superscript),
            Rule(regex: re(#"\[\^[^\]\s]+\]"#), style: .footnote),
            Rule(regex: re(#"^[ \t]*>.*$"#), style: .blockquote),
            Rule(regex: re(#"^[ \t]*[-*+][ \t]+\[[ xX]\]"#), style: .taskMarker),
            Rule(regex: re(#"^[ \t]*([-*+]|\d+[.)])[ \t]+"#), style: .listMarker),
            Rule(regex: re(#"^[ \t]*[|].*[|][ \t]*$"#), style: .table),
            Rule(regex: re(#"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#), style: .thematicBreak),
        ]
    }

    // REQ-040: pure function — takes the text by value, returns styled ranges. Never mutates text.
    func tokens(for text: String) -> [Token] {
        let full = NSRange(location: 0, length: (text as NSString).length)
        var result: [Token] = []
        headingRegex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match else { return }
            let level = match.range(at: 1).length
            result.append(Token(range: match.range, style: .heading(level: min(max(level, 1), 6))))
        }
        for rule in rules {
            rule.regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                guard let match else { return }
                result.append(Token(range: match.range, style: rule.style))
            }
        }
        return result
    }
}
