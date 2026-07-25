//
//  MarkdownHighlighter.swift
//  Markdown Editor
//

import Foundation

// REQ-041/043/047–051: compute style tokens for Markdown source via regex + focused
// scanners (ADR-0009), off the main actor (ADR-0010). Lexical presentation aid only —
// not a conforming parser. Dialect labels: CommonMark 0.31.2 + formal GFM 0.29-gfm (ADR-0003).
actor MarkdownHighlighter {
    private struct Rule {
        let regex: NSRegularExpression
        let style: TokenStyle
        /// When true, matches that overlap an exclusive (code) range are skipped.
        let skipIfExclusiveCovered: Bool
    }

    private let headingRegex: NSRegularExpression
    private let inlineCodeRegex: NSRegularExpression
    private let rules: [Rule]

    init() {
        func re(_ pattern: String) -> NSRegularExpression {
            // Patterns are compile-time constants; a failure here is a programmer error.
            try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }
        headingRegex = re(#"^(#{1,6})[ \t]+\S.*$"#)
        inlineCodeRegex = re(#"`[^`\n]+`"#)

        // Image: focused CommonMark destination forms — angled `<…>`, optional title,
        // backslash escapes, and up to one nested level of balanced parentheses (REQ-050).
        // Not a complete nested-grammar parser.
        let imagePattern = #"""
        !\[[^\]]*\]\(\s*(?:<[^>\n]*>|(?:[^()\s\\]|\\.|(\((?:[^()\s\\]|\\.|\([^()\s\\]*\))*\)))+)(?:\s+(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\((?:[^)\\]|\\.)*\)))?\s*\)
        """#.trimmingCharacters(in: .whitespacesAndNewlines)

        rules = [
            Rule(regex: re(imagePattern), style: .image, skipIfExclusiveCovered: true),
            Rule(regex: re(#"\[[^\]]*\]\([^)\s]*\)"#), style: .link, skipIfExclusiveCovered: true),
            Rule(regex: re(#"\*\*[^\n]+?\*\*"#), style: .bold, skipIfExclusiveCovered: true),
            Rule(regex: re(#"__[^\n]+?__"#), style: .bold, skipIfExclusiveCovered: true),
            Rule(regex: re(#"(?<![*\w])\*(?!\*)[^\n*]+?\*(?!\*)"#), style: .italic, skipIfExclusiveCovered: true),
            Rule(regex: re(#"(?<![_\w])_(?!_)[^\n_]+?_(?!_)"#), style: .italic, skipIfExclusiveCovered: true),
            Rule(regex: re(#"^[ \t]*>.*$"#), style: .blockquote, skipIfExclusiveCovered: true),
            Rule(regex: re(#"^[ \t]*[-*+][ \t]+\[[ xX]\]"#), style: .taskMarker, skipIfExclusiveCovered: true),
            Rule(regex: re(#"^[ \t]*([-*+]|\d+[.)])[ \t]+"#), style: .listMarker, skipIfExclusiveCovered: true),
            // GFM tables may omit leading/trailing pipes (`a | b`).
            Rule(regex: re(#"^[ \t]*\|?[^|\n]+\|[^|\n]+(\|[^|\n]+)*\|?[ \t]*$"#), style: .table, skipIfExclusiveCovered: true),
            Rule(regex: re(#"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#), style: .thematicBreak, skipIfExclusiveCovered: true),
        ]
    }

    // REQ-040/051: pure function — takes the text by value, returns styled ranges. Never mutates text.
    // Observes Task cancellation between passes so superseded highlight work stops early (ADR-0010).
    func tokens(for text: String) throws -> [Token] {
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)
        var result: [Token] = []
        var exclusiveRanges: [NSRange] = []

        try Task.checkCancellation()
        headingRegex.enumerateMatches(in: text, options: [], range: full) { match, _, stop in
            if Task.isCancelled { stop.pointee = true; return }
            guard let match else { return }
            let level = match.range(at: 1).length
            result.append(Token(range: match.range, style: .heading(level: min(max(level, 1), 6))))
        }
        try Task.checkCancellation()

        // CommonMark fenced code (0.31.2 §4.5): indent ≤3, closer length ≥ opener, unclosed → EOF.
        for range in Self.fencedCodeRanges(in: nsText) {
            result.append(Token(range: range, style: .codeBlock))
            exclusiveRanges.append(range)
        }
        try Task.checkCancellation()

        inlineCodeRegex.enumerateMatches(in: text, options: [], range: full) { match, _, stop in
            if Task.isCancelled { stop.pointee = true; return }
            guard let match else { return }
            if Self.overlapsAny(match.range, exclusiveRanges) { return }
            result.append(Token(range: match.range, style: .inlineCode))
            exclusiveRanges.append(match.range)
        }
        try Task.checkCancellation()

        // Formal GFM strikethrough: soft breaks allowed; blank line terminates; escape parity.
        for range in Self.strikethroughRanges(in: nsText) {
            if Self.overlapsAny(range, exclusiveRanges) { continue }
            result.append(Token(range: range, style: .strikethrough))
        }
        try Task.checkCancellation()

        for rule in rules {
            try Task.checkCancellation()
            rule.regex.enumerateMatches(in: text, options: [], range: full) { match, _, stop in
                if Task.isCancelled { stop.pointee = true; return }
                guard let match else { return }
                if rule.skipIfExclusiveCovered, Self.overlapsAny(match.range, exclusiveRanges) {
                    return
                }
                result.append(Token(range: match.range, style: rule.style))
            }
        }
        try Task.checkCancellation()
        return result
    }

    // MARK: - Fenced code (CommonMark §4.5, lexical)

    /// Returns ranges covering each fenced code block including opener and closer lines.
    nonisolated static func fencedCodeRanges(in nsText: NSString) -> [NSRange] {
        let length = nsText.length
        guard length > 0 else { return [] }
        var ranges: [NSRange] = []
        var lineStart = 0

        while lineStart < length {
            let lineEnd = nextLineEnd(in: nsText, from: lineStart)
            let lineContentEnd = trimTrailingNewline(in: nsText, lineStart: lineStart, lineEnd: lineEnd)

            if let opener = fenceOpener(in: nsText, lineStart: lineStart, lineContentEnd: lineContentEnd) {
                var search = lineEnd
                var closerEnd: Int?
                while search < length {
                    let sLineStart = search
                    let sLineEnd = nextLineEnd(in: nsText, from: sLineStart)
                    let sContentEnd = trimTrailingNewline(in: nsText, lineStart: sLineStart, lineEnd: sLineEnd)
                    if isFenceCloser(in: nsText, lineStart: sLineStart, lineContentEnd: sContentEnd,
                                     marker: opener.marker, minimumLength: opener.length) {
                        closerEnd = sLineEnd
                        break
                    }
                    search = sLineEnd
                }
                // Unclosed fence continues to the end of the document (container end).
                let blockEnd = closerEnd ?? length
                ranges.append(NSRange(location: lineStart, length: blockEnd - lineStart))
                lineStart = blockEnd
                continue
            }
            lineStart = lineEnd
        }
        return ranges
    }

    private struct FenceOpener {
        let marker: unichar  // ` or ~
        let length: Int
    }

    private nonisolated static func fenceOpener(
        in nsText: NSString, lineStart: Int, lineContentEnd: Int
    ) -> FenceOpener? {
        var i = lineStart
        var indent = 0
        while i < lineContentEnd {
            let ch = nsText.character(at: i)
            if ch == 0x20 { indent += 1; if indent > 3 { return nil }; i += 1; continue }
            if ch == 0x09 { return nil }  // tabs don't count as the ≤3-space indent here
            break
        }
        guard i < lineContentEnd else { return nil }
        let marker = nsText.character(at: i)
        guard marker == 0x60 || marker == 0x7E else { return nil }  // ` or ~
        var run = 0
        while i + run < lineContentEnd, nsText.character(at: i + run) == marker { run += 1 }
        guard run >= 3 else { return nil }
        // Info string: backtick fences cannot contain backticks in the info string.
        let infoStart = i + run
        if marker == 0x60 {
            for j in infoStart..<lineContentEnd where nsText.character(at: j) == 0x60 {
                return nil
            }
        }
        return FenceOpener(marker: marker, length: run)
    }

    private nonisolated static func isFenceCloser(
        in nsText: NSString, lineStart: Int, lineContentEnd: Int,
        marker: unichar, minimumLength: Int
    ) -> Bool {
        var i = lineStart
        var indent = 0
        while i < lineContentEnd {
            let ch = nsText.character(at: i)
            if ch == 0x20 { indent += 1; if indent > 3 { return false }; i += 1; continue }
            if ch == 0x09 { return false }
            break
        }
        guard i < lineContentEnd else { return false }
        guard nsText.character(at: i) == marker else { return false }
        var run = 0
        while i + run < lineContentEnd, nsText.character(at: i + run) == marker { run += 1 }
        guard run >= minimumLength else { return false }
        // Only spaces/tabs after the closing run.
        var j = i + run
        while j < lineContentEnd {
            let ch = nsText.character(at: j)
            guard ch == 0x20 || ch == 0x09 else { return false }
            j += 1
        }
        return true
    }

    // MARK: - Strikethrough (formal GFM 0.29-gfm)

    /// Matching runs of exactly one or two tildes. Soft line breaks allowed; a blank line
    /// terminates. Delimiters respect backslash escape parity (odd = escaped).
    nonisolated static func strikethroughRanges(in nsText: NSString) -> [NSRange] {
        let length = nsText.length
        guard length > 0 else { return [] }
        var ranges: [NSRange] = []
        var i = 0

        while i < length {
            guard let open = tildeRun(in: nsText, at: i) else {
                i += 1
                continue
            }
            // Escaped first tilde: skip only that character so a following unescaped run can open.
            if open.escaped {
                i += 1
                continue
            }
            // Formal GFM: only runs of length 1 or 2 create strikethrough (Ex. 493).
            guard open.length == 1 || open.length == 2 else {
                i = open.end
                continue
            }
            // Left-flanking: not followed by whitespace.
            guard open.end < length, !isWhitespace(nsText.character(at: open.end)) else {
                i = open.end
                continue
            }

            // Scan for a matching closer before a blank line.
            var j = open.end
            var found: (start: Int, end: Int)?
            while j < length {
                let ch = nsText.character(at: j)
                if ch == 0x0A {  // LF
                    // Blank line (paragraph break) ceases strikethrough (GFM Ex. 492).
                    if j + 1 < length, nsText.character(at: j + 1) == 0x0A { break }
                    // Soft break: continue.
                    j += 1
                    continue
                }
                if ch == 0x0D {  // CR — treat CRLF / lone CR similarly
                    let next = j + 1
                    if next < length, nsText.character(at: next) == 0x0A {
                        if next + 1 < length, nsText.character(at: next + 1) == 0x0A { break }
                        if next + 1 < length, nsText.character(at: next + 1) == 0x0D { break }
                        j = next + 1
                        continue
                    }
                    if next < length, nsText.character(at: next) == 0x0D { break }
                    j += 1
                    continue
                }

                if let close = tildeRun(in: nsText, at: j), !close.escaped {
                    if close.length == open.length {
                        // Right-flanking: not preceded by whitespace.
                        if j > 0, isWhitespace(nsText.character(at: j - 1)) {
                            j = close.end
                            continue
                        }
                        found = (j, close.end)
                        break
                    }
                    // Runs are atomic — never split a longer run to satisfy a shorter closer.
                    j = close.end
                    continue
                }
                j += 1
            }

            if let found {
                ranges.append(NSRange(location: open.start, length: found.end - open.start))
                i = found.end
            } else {
                i = open.end
            }
        }
        return ranges
    }

    private struct TildeRun {
        let start: Int
        let end: Int
        let length: Int
        let escaped: Bool
    }

    /// A maximal run of `~` starting at `at`, with escape parity of the first tilde.
    private nonisolated static func tildeRun(in nsText: NSString, at index: Int) -> TildeRun? {
        let length = nsText.length
        guard index < length, nsText.character(at: index) == 0x7E else { return nil }
        var run = 0
        while index + run < length, nsText.character(at: index + run) == 0x7E { run += 1 }
        return TildeRun(start: index, end: index + run, length: run, escaped: isEscaped(in: nsText, at: index))
    }

    /// Odd number of consecutive `\` immediately before `index` ⇒ character is escaped.
    private nonisolated static func isEscaped(in nsText: NSString, at index: Int) -> Bool {
        var count = 0
        var i = index - 1
        while i >= 0, nsText.character(at: i) == 0x5C {
            count += 1
            i -= 1
        }
        return count % 2 == 1
    }

    private nonisolated static func isWhitespace(_ ch: unichar) -> Bool {
        ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D || ch == 0x0C
    }

    private nonisolated static func nextLineEnd(in nsText: NSString, from lineStart: Int) -> Int {
        let length = nsText.length
        var i = lineStart
        while i < length {
            let ch = nsText.character(at: i)
            if ch == 0x0A { return i + 1 }
            if ch == 0x0D {
                if i + 1 < length, nsText.character(at: i + 1) == 0x0A { return i + 2 }
                return i + 1
            }
            i += 1
        }
        return length
    }

    private nonisolated static func trimTrailingNewline(
        in nsText: NSString, lineStart: Int, lineEnd: Int
    ) -> Int {
        var end = lineEnd
        if end > lineStart, nsText.character(at: end - 1) == 0x0A { end -= 1 }
        if end > lineStart, nsText.character(at: end - 1) == 0x0D { end -= 1 }
        return end
    }

    private nonisolated static func overlapsAny(_ range: NSRange, _ others: [NSRange]) -> Bool {
        others.contains { NSIntersectionRange(range, $0).length > 0 }
    }
}
