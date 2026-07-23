//
//  TextStats.swift
//  Markdown Editor
//

import Foundation

// REQ-044: word / character counts. Pure and testable.
nonisolated enum TextStats {
    struct Counts: Sendable, Equatable {
        let words: Int
        let characters: Int
    }

    static func counts(_ text: String) -> Counts {
        Counts(words: wordCount(text), characters: characterCount(text))
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0.isNewline }).count
    }

    static func characterCount(_ text: String) -> Int {
        text.count
    }
}
