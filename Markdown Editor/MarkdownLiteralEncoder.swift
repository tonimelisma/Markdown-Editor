//
//  MarkdownLiteralEncoder.swift
//  Markdown Editor
//

import Foundation

/// Context for choosing the minimum safe formal-GFM source spelling of literal text.
///
/// // REQ-092; ARC-008: typing is not a formatting command.
nonisolated struct LiteralEncodeContext: Sendable, Equatable {
    let intendedVisibleText: String
    let precedingSourceCharacter: Character?
    let followingSourceCharacter: Character?
    let atLineStart: Bool
    let container: LiteralContainer
    let dialect: LiteralDialect

    enum LiteralContainer: Sendable, Equatable {
        case paragraph
        case heading
        case blockQuote
        case listItem
        case tableCell
        case linkLabel
        case emphasis
        case strong
    }

    enum LiteralDialect: Sendable, Equatable {
        case formalGFM
    }
}

nonisolated enum LiteralEncodeResult: Sendable, Equatable {
    case encoded(String)
    case refused
}

/// Derives the minimum source spelling that reparses to the intended literal content.
///
/// // REQ-092; ARC-008: may escape punctuation in source while WYSIWYG shows the literal character.
nonisolated enum MarkdownLiteralEncoder {
    static func encode(_ context: LiteralEncodeContext) -> LiteralEncodeResult {
        guard context.dialect == .formalGFM else { return .refused }
        let text = context.intendedVisibleText
        guard !text.isEmpty else { return .encoded("") }

        var output = String()
        output.reserveCapacity(text.utf16.count * 2)

        var index = text.startIndex
        var columnIsLineStart = context.atLineStart
        while index < text.endIndex {
            let ch = text[index]
            let nextIndex = text.index(after: index)
            let next = nextIndex < text.endIndex ? text[nextIndex] : context.followingSourceCharacter

            if needsEscape(ch, atLineStart: columnIsLineStart, next: next, container: context.container, preceding: index == text.startIndex ? context.precedingSourceCharacter : text[text.index(before: index)]) {
                output.append("\\")
                output.append(ch)
            } else if ch == "&" {
                // Keep ampersand literal when it does not begin a valid entity that would decode differently.
                // Prefer numeric entity only when followed by entity-like text that cmark would consume.
                if looksLikeEntityStart(text, from: index) {
                    output.append("&amp;")
                } else {
                    output.append("&")
                }
            } else if ch == "<" {
                output.append("&lt;")
            } else if ch == ">" {
                // Escape '>' when it could start HTML or close an autolink-like span.
                output.append("&gt;")
            } else if ch == "|" && context.container == .tableCell {
                output.append("\\|")
            } else {
                output.append(ch)
            }

            columnIsLineStart = (ch == "\n")
            index = nextIndex
        }

        return .encoded(output)
    }

    /// Decode a concrete atomic source span according to pinned CommonMark/GFM rules for known kinds.
    static func decode(sourceSpelling: String, kind: AtomicRepresentationKind) -> String? {
        switch kind {
        case .backslashEscape:
            guard sourceSpelling.count >= 2, sourceSpelling.first == "\\" else { return nil }
            return String(sourceSpelling.dropFirst())
        case .htmlEntity:
            return decodeHTMLEntity(sourceSpelling)
        case .taskMarker, .softBreak, .hardBreak:
            return nil
        case .normalizedCodeBlock:
            // CRLF source normalises to LF in the cmark literal: each "\r\n" in source maps to "\n" visible.
            return sourceSpelling.replacingOccurrences(of: "\r\n", with: "\n")
        }
    }

    /// Encode a visible atomic span back to its concrete source spelling.
    static func encode(decoded: String, kind: AtomicRepresentationKind) -> String? {
        switch kind {
        case .normalizedCodeBlock:
            // Uniform inverse: correct for uniform CRLF files (the common case) and for LF
            // identity (no \r\n in decoded path). Mixed line endings are preserved per-line
            // via the atomic path (each \r\n is one .normalizedCodeBlock atom), not via this
            // helper, so uniform re-expansion cannot over-expand a mixed file's untouched lines.
            return decoded.replacingOccurrences(of: "\n", with: "\r\n")
        default:
            return nil
        }
    }

    /// Per-line inverse for mixed line endings: re-expand each "\n" using the original source's
    /// per-line terminator, so editing line *i* leaves every other line's terminator byte-identical.
    static func encode(decoded: String, kind: AtomicRepresentationKind, originalSource: String) -> String? {
        guard kind == .normalizedCodeBlock else { return nil }
        if !originalSource.contains("\r\n") { return decoded }
        // Collect terminators from originalSource in order.
        var terminators: [String] = []
        var idx = originalSource.startIndex
        while idx < originalSource.endIndex {
            guard let nl = originalSource[idx...].firstIndex(of: "\n") else { break }
            let isCRLF: Bool = {
                if nl == originalSource.startIndex { return false }
                return originalSource[originalSource.index(before: nl)] == "\r"
            }()
            terminators.append(isCRLF ? "\r\n" : "\n")
            idx = originalSource.index(after: nl)
            if idx >= originalSource.endIndex { break }
        }
        let decodedLines = decoded.split(separator: "\n", omittingEmptySubsequences: false)
        var result = ""
        for i in 0..<decodedLines.count {
            result += decodedLines[i]
            if i < decodedLines.count - 1 {
                if i < terminators.count {
                    result += terminators[i]
                } else {
                    result += "\r\n"
                }
            }
        }
        return result
    }

    // MARK: - Helpers

    private static func needsEscape(
        _ ch: Character,
        atLineStart: Bool,
        next: Character?,
        container: LiteralEncodeContext.LiteralContainer,
        preceding: Character?
    ) -> Bool {
        switch ch {
        case "\\", "[", "]", "`":
            return true
        case "*":
            // Escape emphasis opener/closer candidates.
            return true
        case "_":
            // Escape when flanked in a way CommonMark treats as emphasis.
            let leftFlank = preceding.map { !$0.isWhitespace && $0 != "_" } ?? false
            let rightFlank = next.map { !$0.isWhitespace && $0 != "_" } ?? false
            return leftFlank || rightFlank || preceding == nil || next == nil
        case "~":
            return next == "~" || preceding == "~"
        case "#":
            return atLineStart
        case ">":
            return atLineStart
        case "-", "+", "=":
            // Potential setext / thematic break / list marker at line start.
            return atLineStart
        case "!":
            return next == "["
        case "(":
            return false
        case ")":
            return false
        default:
            if container == .tableCell && ch == "|" { return true }
            return false
        }
    }

    private static func looksLikeEntityStart(_ text: String, from index: String.Index) -> Bool {
        guard text[index] == "&" else { return false }
        var i = text.index(after: index)
        guard i < text.endIndex else { return false }
        if text[i] == "#" {
            i = text.index(after: i)
            guard i < text.endIndex else { return false }
            let isHex = text[i] == "x" || text[i] == "X"
            if isHex { i = text.index(after: i) }
            var digits = 0
            while i < text.endIndex {
                let c = text[i]
                if isHex {
                    guard c.isHexDigit else { break }
                } else {
                    guard c.isNumber else { break }
                }
                digits += 1
                i = text.index(after: i)
            }
            return digits > 0 && i < text.endIndex && text[i] == ";"
        }
        var letters = 0
        while i < text.endIndex {
            let c = text[i]
            guard c.isLetter || c.isNumber else { break }
            letters += 1
            i = text.index(after: i)
        }
        return letters > 0 && i < text.endIndex && text[i] == ";"
    }

    private static func decodeHTMLEntity(_ spelling: String) -> String? {
        // Minimal named/numeric decode for atomic atoms already classified by the compiler.
        guard spelling.hasPrefix("&"), spelling.hasSuffix(";") else { return nil }
        let inner = spelling.dropFirst().dropLast()
        if inner.hasPrefix("#x") || inner.hasPrefix("#X") {
            let hex = inner.dropFirst(2)
            guard let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) else { return nil }
            return String(Character(scalar))
        }
        if inner.hasPrefix("#") {
            let dec = inner.dropFirst()
            guard let value = UInt32(dec), let scalar = UnicodeScalar(value) else { return nil }
            return String(Character(scalar))
        }
        switch String(inner) {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return "\u{00A0}"
        default: return nil
        }
    }
}
