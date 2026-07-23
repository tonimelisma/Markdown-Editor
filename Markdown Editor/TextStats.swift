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

// REQ-044/045: serializes count work away from the main actor and observes cancellation while
// scanning, so a superseded snapshot stops promptly instead of competing with current typing.
actor TextStatsComputer {
    func counts(for text: String) -> TextStats.Counts? {
        var words = 0
        var characters = 0
        var isInWord = false

        for character in text {
            if Task.isCancelled { return nil }
            characters += 1
            if character == " " || character == "\t" || character.isNewline {
                isInWord = false
            } else if !isInWord {
                words += 1
                isInWord = true
            }
        }

        return .init(words: words, characters: characters)
    }
}
