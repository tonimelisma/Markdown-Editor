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
    private var cachedIndex = SourceLineIndex(source: "")
    private let lineHighlighter = MarkdownHighlighter()

    func reset() {
        cache.removeAll(keepingCapacity: true)
        cachedSource = ""
        cachedIndex = SourceLineIndex(source: "")
    }

    func highlight(
        source: String,
        editedRange: NSRange?,
        sourceRevision: UInt64,
        intentID: IntentID?
    ) async throws -> SourceHighlightPatch {
        let index = SourceLineIndex.updating(
            source: source,
            previousSource: cachedSource,
            previous: cachedIndex,
            editedRange: editedRange
        )
        guard !index.lines.isEmpty else {
            cache = []
            cachedSource = source
            cachedIndex = index
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
        let oldIndex = cachedIndex
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
            let changed = old.map { !$0.hasSameLexicalResult(as: lexed) } ?? true
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
               old!.hasSameLexicalResult(as: lexed) {
                next.append(contentsOf: oldCache[line...].enumerated().map { offset, cachedLine in
                    cachedLine.rebased(to: index.lines[line + offset])
                })
                break
            }
        }

        cache = next
        cachedSource = source
        cachedIndex = index
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
        let crossLineStrike = Self.crossLineStrikethrough(
            in: local,
            contentEnd: contentEnd,
            incomingOpen: incoming.strikethroughOpen,
            range: range
        )
        let tokens = localTokens.map {
            Token(range: NSRange(location: range.location + $0.range.location, length: $0.range.length), style: $0.style)
        }
        let outgoing = SourceLexState(fence: nil, strikethroughOpen: crossLineStrike.outgoingOpen)
        return SourceLexedLine(
            text: text,
            range: range,
            incoming: incoming,
            outgoing: outgoing,
            tokens: tokens + crossLineStrike.tokens
        )
    }

    private static func crossLineStrikethrough(
        in text: NSString,
        contentEnd: Int,
        incomingOpen: Bool,
        range: NSRange
    ) -> (outgoingOpen: Bool, tokens: [Token]) {
        guard contentEnd > 0 else { return (false, []) }

        func isDoubleTilde(at index: Int) -> Bool {
            guard index + 1 < contentEnd,
                  text.character(at: index) == 0x7E,
                  text.character(at: index + 1) == 0x7E,
                  (index == 0 || text.character(at: index - 1) != 0x7E),
                  (index + 2 >= contentEnd || text.character(at: index + 2) != 0x7E) else { return false }
            var slashCount = 0
            var cursor = index - 1
            while cursor >= 0, text.character(at: cursor) == 0x5C { slashCount += 1; cursor -= 1 }
            return slashCount.isMultiple(of: 2)
        }

        func nextDelimiter(after start: Int) -> Int? {
            guard start < contentEnd else { return nil }
            for index in start..<contentEnd where isDoubleTilde(at: index) {
                return index
            }
            return nil
        }

        if incomingOpen {
            if let closer = nextDelimiter(after: 0) {
                return (
                    false,
                    [Token(range: NSRange(location: range.location, length: closer + 2), style: .strikethrough)]
                )
            }
            return (
                true,
                [Token(range: NSRange(location: range.location, length: contentEnd), style: .strikethrough)]
            )
        }

        guard let opener = nextDelimiter(after: 0),
              opener + 2 < contentEnd,
              !Self.isWhitespace(text.character(at: opener + 2)) else { return (false, []) }
        guard nextDelimiter(after: opener + 2) == nil else { return (false, []) }
        return (
            true,
            [Token(range: NSRange(location: range.location + opener, length: contentEnd - opener), style: .strikethrough)]
        )
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09 || character == 0x0A || character == 0x0D
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
