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

    static let initial = SourceLexState(fence: nil)
}

nonisolated struct SourceLexedLine: Sendable, Equatable {
    let text: String
    let range: NSRange
    let incoming: SourceLexState
    let outgoing: SourceLexState
    let tokens: [Token]
}
