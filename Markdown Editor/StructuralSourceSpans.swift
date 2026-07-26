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
    /// Body of an inline code span: skip opening backticks, take rendered UTF-16 length.
    static func inlineCodeBody(
        full: NSRange,
        rendered: String,
        map: SourceCoordinateMap
    ) -> NSRange? {
        guard case .success(let slice) = map.substring(utf16: full) else { return nil }
        let ns = slice as NSString
        var i = 0
        while i < ns.length {
            let c = ns.character(at: i)
            if c != 0x60 { break } // '`'
            i += 1
        }
        guard i > 0 else { return nil }
        let bodyLength = (rendered as NSString).length
        guard i + bodyLength <= ns.length else { return nil }
        return NSRange(location: full.location + i, length: bodyLength)
    }

    /// Body of a fenced code block from opening-fence / closing-fence line boundaries.
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
            if c == 0x20 { // space
                indent += 1
                idx += 1
            } else if c == 0x09 { // tab counts as indent stop
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
        // Skip info string to end of line.
        while idx < ns.length {
            let c = ns.character(at: idx)
            idx += 1
            if c == 0x0A { break } // LF
            if c == 0x0D {
                if idx < ns.length, ns.character(at: idx) == 0x0A { idx += 1 }
                break
            }
        }
        let bodyStartInSlice = idx
        let renderedUTF16 = (rendered as NSString).length
        // Prefer concrete rendered length (compiler may append a trailing newline).
        let bodyLength: Int
        if bodyStartInSlice + renderedUTF16 <= ns.length {
            bodyLength = renderedUTF16
        } else {
            let literalUTF16 = (literal as NSString).length
            guard bodyStartInSlice + literalUTF16 <= ns.length else { return nil }
            bodyLength = literalUTF16
        }
        _ = info // info is structural context; body starts after the opening line regardless.
        return NSRange(location: full.location + bodyStartInSlice, length: bodyLength)
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
