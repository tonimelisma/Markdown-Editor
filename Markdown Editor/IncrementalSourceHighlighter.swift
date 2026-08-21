//
//  IncrementalSourceHighlighter.swift
//  Markdown Editor
//

import Foundation

/// A stateful line lexer. It owns only immutable source-line snapshots; all mutable cache state
/// stays in this actor so cancelled/replaced demands cannot race one another.
///
/// // REQ-040/041/043/045; ARC-020: ordinary edits never invoke a whole-source lexer or fence scan.
actor IncrementalSourceHighlighter {
    private var cache: [SourceLexedLine] = []
    private var cachedSource: String = ""
    private let lineHighlighter = MarkdownHighlighter()

    func reset() {
        cache.removeAll(keepingCapacity: true)
        cachedSource = ""
    }

    func highlight(
        source: String,
        editedRange: NSRange?,
        sourceRevision: UInt64,
        intentID: IntentID?
    ) async throws -> SourceHighlightPatch {
        let index = SourceLineIndex(source: source)
        guard !index.lines.isEmpty else {
            cache = []
            cachedSource = source
            return SourceHighlightPatch(
                sourceRevision: sourceRevision,
                sourceUTF16Count: index.sourceUTF16Count,
                tokens: [],
                changedRanges: [],
                scannedLineCount: 0,
                lexedUTF16Count: 0,
                intentID: intentID
            )
        }

        let ns = source as NSString
        let oldCache = cache
        let oldIndex = SourceLineIndex(source: cachedSource)
        let startLine: Int
        if oldCache.isEmpty {
            startLine = 0
        } else if let editedRange {
            startLine = min(index.affectedLine(for: editedRange), index.lines.count - 1)
        } else {
            startLine = 0
        }

        var next = Array(oldCache.prefix(min(startLine, index.lines.count)))
        if next.count < startLine { next.removeAll(keepingCapacity: true) }
        var incoming = startLine == 0 ? .initial : (next.last?.outgoing ?? .initial)
        var changedRanges: [NSRange] = []
        var changedTokens: [Token] = []
        var scannedLineCount = 0
        var lexedUTF16Count = 0
        var line = startLine

        while line < index.lines.count {
            try Task.checkCancellation()
            let range = index.lines[line]
            let text = ns.substring(with: range)
            let lexed = try await lexLine(text: text, range: range, incoming: incoming)
            scannedLineCount += 1
            lexedUTF16Count += range.length
            next.append(lexed)

            let old = oldCache.indices.contains(line) ? oldCache[line] : nil
            let changed = old != lexed
            if changed {
                changedRanges.append(range)
                changedTokens.append(contentsOf: lexed.tokens)
            }

            incoming = lexed.outgoing
            line += 1

            // A same-index, same-text line with equal incoming/outgoing state proves that the
            // tail is unaffected only when line topology did not change. Otherwise continue to
            // the end so a line insertion/deletion cannot reuse a shifted cache entry.
            if !oldCache.isEmpty,
               oldIndex.lines.count == index.lines.count,
               line < index.lines.count,
               old != nil,
               old?.text == lexed.text,
               old?.incoming == lexed.incoming,
               old?.outgoing == lexed.outgoing {
                next.append(contentsOf: oldCache[line...])
                break
            }
        }

        cache = next
        cachedSource = source
        return SourceHighlightPatch(
            sourceRevision: sourceRevision,
            sourceUTF16Count: index.sourceUTF16Count,
            tokens: changedTokens,
            changedRanges: changedRanges,
            scannedLineCount: scannedLineCount,
            lexedUTF16Count: lexedUTF16Count,
            intentID: intentID
        )
    }

    private func lexLine(
        text: String,
        range: NSRange,
        incoming: SourceLexState
    ) async throws -> SourceLexedLine {
        let local = text as NSString
        let contentEnd = Self.contentEnd(in: local)
        if let fence = incoming.fence {
            let closes = Self.isFenceCloser(
                in: local,
                contentEnd: contentEnd,
                marker: fence.marker,
                minimumLength: fence.minimumLength
            )
            return SourceLexedLine(
                text: text,
                range: range,
                incoming: incoming,
                outgoing: closes ? .initial : incoming,
                tokens: [Token(range: range, style: .codeBlock)]
            )
        }

        if let opener = Self.fenceOpener(in: local, contentEnd: contentEnd) {
            return SourceLexedLine(
                text: text,
                range: range,
                incoming: incoming,
                outgoing: SourceLexState(fence: .init(marker: opener.marker, minimumLength: opener.length)),
                tokens: [Token(range: range, style: .codeBlock)]
            )
        }

        let localTokens = try await lineHighlighter.tokens(for: text)
        let tokens = localTokens.map {
            Token(range: NSRange(location: range.location + $0.range.location, length: $0.range.length), style: $0.style)
        }
        return SourceLexedLine(
            text: text,
            range: range,
            incoming: incoming,
            outgoing: .initial,
            tokens: tokens
        )
    }

    private static func contentEnd(in text: NSString) -> Int {
        var end = text.length
        if end > 0, text.character(at: end - 1) == 0x0A { end -= 1 }
        if end > 0, text.character(at: end - 1) == 0x0D { end -= 1 }
        return end
    }

    private static func fenceOpener(in text: NSString, contentEnd: Int) -> (marker: UInt16, length: Int)? {
        var index = 0
        var indent = 0
        while index < contentEnd, text.character(at: index) == 0x20 {
            indent += 1
            if indent > 3 { return nil }
            index += 1
        }
        guard index < contentEnd else { return nil }
        let marker = text.character(at: index)
        guard marker == 0x60 || marker == 0x7E else { return nil }
        var length = 0
        while index + length < contentEnd, text.character(at: index + length) == marker { length += 1 }
        guard length >= 3 else { return nil }
        if marker == 0x60 {
            for position in (index + length)..<contentEnd where text.character(at: position) == marker { return nil }
        }
        return (marker, length)
    }

    private static func isFenceCloser(
        in text: NSString,
        contentEnd: Int,
        marker: UInt16,
        minimumLength: Int
    ) -> Bool {
        var index = 0
        var indent = 0
        while index < contentEnd, text.character(at: index) == 0x20 {
            indent += 1
            if indent > 3 { return false }
            index += 1
        }
        guard index < contentEnd, text.character(at: index) == marker else { return false }
        var length = 0
        while index + length < contentEnd, text.character(at: index + length) == marker { length += 1 }
        guard length >= minimumLength else { return false }
        for position in (index + length)..<contentEnd {
            let character = text.character(at: position)
            if character != 0x20 && character != 0x09 { return false }
        }
        return true
    }
}

nonisolated struct SourceHighlightPatch: Sendable, Equatable {
    let sourceRevision: UInt64
    let sourceUTF16Count: Int
    let tokens: [Token]
    let changedRanges: [NSRange]
    let scannedLineCount: Int
    let lexedUTF16Count: Int
    let intentID: IntentID?
}
