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

    /// The single counting implementation.
    ///
    /// // COR-30: this logic previously existed twice — `TextStats.wordCount`, which REQ-044's
    /// // `countsWordsAndCharacters` tested, and a second differently-written scan inside
    /// // `TextStatsComputer`, which was the one that actually shipped. The requirement's
    /// // correctness proof did not cover the running code.
    ///
    /// `shouldCancel` is consulted on a stride rather than per character: the actor previously
    /// read `Task.isCancelled` once for every character, which is 100,000 task-local reads on
    /// the approved corpus for no added responsiveness.
    static func counts(_ text: String, shouldCancel: () -> Bool = { false }) -> Counts? {
        var words = 0
        var characters = 0
        var isInWord = false
        var sinceCheck = 0
        let cancellationStride = 4096

        for character in text {
            sinceCheck += 1
            if sinceCheck >= cancellationStride {
                sinceCheck = 0
                if shouldCancel() { return nil }
            }
            characters += 1
            if character == " " || character == "\t" || character.isNewline {
                isInWord = false
            } else if !isInWord {
                words += 1
                isInWord = true
            }
        }
        return Counts(words: words, characters: characters)
    }
}

// REQ-044/045: serializes count work away from the main actor and observes cancellation while
// scanning, so a superseded snapshot stops promptly instead of competing with current typing.
actor TextStatsComputer {
    func counts(for text: String) -> TextStats.Counts? {
        TextStats.counts(text, shouldCancel: { Task.isCancelled })
    }
}
