//
//  SourceLexState.swift
//  Markdown Editor
//

import Foundation

/// The lexical state carried from one source line to the next.
///
/// // REQ-040/041/043/045: the state is deliberately closed. A new multiline lexical
/// construct must add a case here and a corresponding line-lexer proof.
nonisolated struct SourceLexState: Sendable, Equatable {
    struct Fence: Sendable, Equatable {
        let marker: UInt16
        let minimumLength: Int
    }

    let fence: Fence?
    let strikethroughOpen: Bool

    static let initial = SourceLexState(fence: nil, strikethroughOpen: false)

    init(fence: Fence?, strikethroughOpen: Bool = false) {
        self.fence = fence
        self.strikethroughOpen = strikethroughOpen
    }
}

nonisolated struct SourceLexedLine: Sendable, Equatable {
    let text: String
    let range: NSRange
    let incoming: SourceLexState
    let outgoing: SourceLexState
    let tokens: [Token]

    func rebased(to newRange: NSRange) -> SourceLexedLine {
        let delta = newRange.location - range.location
        return SourceLexedLine(
            text: text,
            range: newRange,
            incoming: incoming,
            outgoing: outgoing,
            tokens: tokens.map { token in
                Token(
                    range: NSRange(location: token.range.location + delta, length: token.range.length),
                    style: token.style
                )
            }
        )
    }

    func hasSameLexicalResult(as other: SourceLexedLine) -> Bool {
        guard text == other.text, incoming == other.incoming, outgoing == other.outgoing else { return false }
        let rebased = rebased(to: other.range)
        return rebased.tokens == other.tokens
    }
}
