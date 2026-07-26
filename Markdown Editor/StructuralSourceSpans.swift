//
//  StructuralSourceSpans.swift
//  Markdown Editor
//

import Foundation

/// Derives exact UTF-16 source spans from concrete Markdown structure.
///
/// // REQ-057/078/087: fence/task ranges come from fence metadata and line boundaries —
/// // never from substring search of rendered text.
nonisolated enum StructuralSourceSpans {
    /// Body of an inline code span when source bytes equal the rendered literal exactly.
    ///
    /// cmark-gfm code-node positions usually exclude the surrounding backticks and cover the
    /// raw interior (including spaces CommonMark strips from the literal). When that interior
    /// is not identical to `rendered` (e.g. `` ` foo ` `` → `foo`), returns `nil` so callers
    /// refuse rather than invent a shifted span. If the node range still includes ticks, the
    /// body after the opening ticks is accepted only when those bytes equal `rendered`.
    static func inlineCodeBody(
        full: NSRange,
        rendered: String,
        map: SourceCoordinateMap
    ) -> NSRange? {
        guard case .success(let slice) = map.substring(utf16: full) else { return nil }
        // Common case: node span is already the content between ticks.
        if slice == rendered {
            return full
        }
        let ns = slice as NSString
        var i = 0
        while i < ns.length {
            let c = ns.character(at: i)
            if c != 0x60 { break } // '`'
            i += 1
        }
        guard i > 0 else { return nil }
        let openCount = i
        let bodyLength = (rendered as NSString).length
        guard i + bodyLength + openCount <= ns.length else { return nil }
        let candidate = ns.substring(with: NSRange(location: i, length: bodyLength))
        // Exact identity only — refuses normalized spans like `` ` foo ` ``.
        guard candidate == rendered else { return nil }
        for k in 0..<openCount {
            guard ns.character(at: i + bodyLength + k) == 0x60 else { return nil }
        }
        return NSRange(location: full.location + i, length: bodyLength)
    }

    /// Body of a fenced code block when the raw body UTF-16 equals the rendered literal.
    ///
    /// Returns `nil` when CRLF normalization or fence-indent stripping make the raw body
    /// differ from `rendered` — callers must refuse rather than patch shifted bytes.
    static func fencedCodeBody(
        full: NSRange,
        info: String,
        literal: String,
        rendered: String,
        fenceChar: Character,
        fenceLength: Int,
        map: SourceCoordinateMap
    ) -> NSRange? {
        guard case .success(let slice) = map.substring(utf16: full) else { return nil }
        let ns = slice as NSString
        // Opening fence line: optional indent (≤3 spaces), fence chars, optional info, newline.
        var idx = 0
        var indent = 0
        while idx < ns.length, indent < 3 {
            let c = ns.character(at: idx)
            if c == 0x20 {
                indent += 1
                idx += 1
            } else if c == 0x09 {
                idx += 1
                break
            } else {
                break
            }
        }
        let fenceScalar = fenceChar.utf16.first ?? 0x60
        var fenceCount = 0
        while idx < ns.length, ns.character(at: idx) == fenceScalar {
            fenceCount += 1
            idx += 1
        }
        guard fenceCount >= fenceLength else { return nil }
        while idx < ns.length {
            let c = ns.character(at: idx)
            idx += 1
            if c == 0x0A { break }
            if c == 0x0D {
                if idx < ns.length, ns.character(at: idx) == 0x0A { idx += 1 }
                break
            }
        }
        let bodyStartInSlice = idx

        // Closing fence line: scan from the end for a line that is only indent + fence chars.
        var bodyEndInSlice = ns.length
        var search = ns.length
        while search > bodyStartInSlice {
            // Find previous line break.
            var lineEnd = search
            var lineStart = bodyStartInSlice
            var p = search
            while p > bodyStartInSlice {
                p -= 1
                let c = ns.character(at: p)
                if c == 0x0A || c == 0x0D {
                    lineStart = p + 1
                    break
                }
            }
            if p == bodyStartInSlice { lineStart = bodyStartInSlice }

            var q = lineStart
            while q < lineEnd, ns.character(at: q) == 0x20 || ns.character(at: q) == 0x09 {
                q += 1
            }
            var closeCount = 0
            while q < lineEnd, ns.character(at: q) == fenceScalar {
                closeCount += 1
                q += 1
            }
            // Rest of line must be only optional whitespace / CR.
            var onlyWS = true
            while q < lineEnd {
                let c = ns.character(at: q)
                if c != 0x20 && c != 0x09 && c != 0x0D && c != 0x0A {
                    onlyWS = false
                    break
                }
                q += 1
            }
            if closeCount >= fenceLength, onlyWS {
                bodyEndInSlice = lineStart
                break
            }
            search = lineStart > bodyStartInSlice ? lineStart - 1 : bodyStartInSlice
            if search <= bodyStartInSlice { break }
            _ = lineEnd
        }

        guard bodyEndInSlice >= bodyStartInSlice else { return nil }
        let rawBody = ns.substring(
            with: NSRange(location: bodyStartInSlice, length: bodyEndInSlice - bodyStartInSlice)
        )
        // Exact identity only — refuse CRLF / indent-stripped normalization.
        guard rawBody == rendered else { return nil }
        _ = info
        _ = literal
        return NSRange(
            location: full.location + bodyStartInSlice,
            length: (rawBody as NSString).length
        )
    }

    /// Exact three-character task marker (`[ ]` / `[x]` / `[X]`) inside a list-item source span.
    static func taskMarkerRange(
        itemSource: NSRange,
        source: String,
        currentlyChecked: Bool
    ) -> NSRange? {
        let ns = source as NSString
        guard itemSource.location >= 0,
              NSMaxRange(itemSource) <= ns.length else { return nil }
        let slice = ns.substring(with: itemSource) as NSString
        // Scan for the first task checkbox after the list marker on the item's first line.
        var i = 0
        let length = slice.length
        // Skip leading whitespace.
        while i < length {
            let c = slice.character(at: i)
            if c == 0x20 || c == 0x09 { i += 1 } else { break }
        }
        // Skip bullet or ordered marker.
        if i < length {
            let c = slice.character(at: i)
            if c == 0x2D || c == 0x2A || c == 0x2B { // - * +
                i += 1
            } else {
                // Ordered: digits then . or )
                var sawDigit = false
                while i < length {
                    let d = slice.character(at: i)
                    if d >= 0x30 && d <= 0x39 {
                        sawDigit = true
                        i += 1
                    } else {
                        break
                    }
                }
                guard sawDigit, i < length else { return nil }
                let delim = slice.character(at: i)
                guard delim == 0x2E || delim == 0x29 else { return nil } // . )
                i += 1
            }
        }
        // Skip whitespace after marker.
        while i < length {
            let c = slice.character(at: i)
            if c == 0x20 || c == 0x09 { i += 1 } else { break }
        }
        guard i + 3 <= length,
              slice.character(at: i) == 0x5B, // [
              slice.character(at: i + 2) == 0x5D else { // ]
            return nil
        }
        let mid = slice.character(at: i + 1)
        let isChecked = mid == 0x78 || mid == 0x58 // x X
        let isUnchecked = mid == 0x20
        guard (currentlyChecked && isChecked) || (!currentlyChecked && isUnchecked) else {
            return nil
        }
        return NSRange(location: itemSource.location + i, length: 3)
    }
}
