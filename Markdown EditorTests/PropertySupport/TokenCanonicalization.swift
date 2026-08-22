//
//  TokenCanonicalization.swift
//  Markdown EditorTests
//

import Foundation
@testable import Markdown_Editor

/// Canonical form for comparing two token sets that describe the same text.
///
/// A full relex and an incrementally composed set may legitimately differ in token *order* and in
/// how a run is split, while describing identical styling. Canonicalization merges touching or
/// overlapping same-style tokens and imposes a total order, so a comparison fails only on a real
/// styling difference.
///
/// Shared by `IncrementalSourceHighlighterTests` and `PropertyTests` — one implementation, because
/// two copies of an oracle's normalizer can drift and quietly stop agreeing about what "same" means.
enum TokenCanonicalization {
    static func order(_ lhs: Token, _ rhs: Token) -> Bool {
        if lhs.range.location != rhs.range.location { return lhs.range.location < rhs.range.location }
        if lhs.range.length != rhs.range.length { return lhs.range.length < rhs.range.length }
        return String(describing: lhs.style) < String(describing: rhs.style)
    }

    static func canonical(_ tokens: [Token]) -> [Token] {
        let grouped = tokens.reduce(into: [TokenStyle: [Token]]()) { result, token in
            result[token.style, default: []].append(token)
        }
        return grouped.values
            .flatMap { styleTokens in
                styleTokens.sorted(by: order).reduce(into: [Token]()) { result, token in
                    guard let previous = result.last else {
                        result.append(token)
                        return
                    }
                    if NSMaxRange(previous.range) >= token.range.location {
                        result[result.count - 1] = Token(
                            range: NSUnionRange(previous.range, token.range),
                            style: previous.style
                        )
                    } else {
                        result.append(token)
                    }
                }
            }
            .sorted(by: order)
    }

    /// Clips `tokens` to `range`, dropping those that fall outside it.
    ///
    /// Used to compare an incremental patch against a full relex *within the region the patch
    /// claims to have rescanned*. Comparing whole documents instead requires reconstructing the
    /// running token set in post-edit coordinates — in production that shift is done by
    /// `NSTextStorage`, which adjusts attribute ranges on every edit, and a test-side array does
    /// not. Restricting the comparison to the rescanned region removes that confound entirely
    /// while still asking the question that matters: for the lines it re-lexed, did the
    /// incremental lexer produce what a fresh full lexer produces?
    static func clipped(_ tokens: [Token], to range: NSRange) -> [Token] {
        tokens.compactMap { token in
            let intersection = NSIntersectionRange(token.range, range)
            guard intersection.length > 0 else { return nil }
            return Token(range: intersection, style: token.style)
        }
    }
}
