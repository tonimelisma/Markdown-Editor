//
//  GeneratedEditSequence.swift
//  Markdown EditorTests
//

import Foundation

/// Closed edit-operation vocabulary. Adding a case fails the dimension-coverage assertion in
/// `PropertyTests` until the generator can produce it.
///
/// // REQ-132
enum EditOperation: CaseIterable {
    case insertPlainCharacter
    case insertNewline
    case insertFenceMarker
    case deleteBackwardOne
    case deleteRange
    case replaceRange
    case insertAtDocumentStart
    case insertAtDocumentEnd
}

struct GeneratedEdit {
    let operation: EditOperation
    /// UTF-16 range in the source *before* this edit.
    let range: NSRange
    let replacement: String

    var replayDescription: String {
        "\(operation) range=\(NSStringFromRange(range)) replacement=\(replacement.debugDescription)"
    }
}

enum GeneratedEditSequence {
    /// Produces an edit that is always valid against `source`, so a property failure is about the
    /// system under test rather than about a nonsensical input.
    static func edit(
        _ operation: EditOperation,
        in source: String,
        rng: inout DeterministicRNG
    ) -> GeneratedEdit {
        let ns = source as NSString
        let length = ns.length

        func safeLocation() -> Int {
            guard length > 0 else { return 0 }
            // Never split a surrogate pair or a composed grapheme: align to a composed boundary.
            let raw = rng.next(below: length)
            return ns.rangeOfComposedCharacterSequence(at: raw).location
        }

        switch operation {
        case .insertPlainCharacter:
            return GeneratedEdit(operation: operation, range: NSRange(location: safeLocation(), length: 0), replacement: "x")
        case .insertNewline:
            return GeneratedEdit(operation: operation, range: NSRange(location: safeLocation(), length: 0), replacement: "\n")
        case .insertFenceMarker:
            return GeneratedEdit(operation: operation, range: NSRange(location: safeLocation(), length: 0), replacement: "```")
        case .deleteBackwardOne:
            guard length > 0 else {
                return GeneratedEdit(operation: operation, range: NSRange(location: 0, length: 0), replacement: "")
            }
            let location = safeLocation()
            let composed = ns.rangeOfComposedCharacterSequence(at: location)
            return GeneratedEdit(operation: operation, range: composed, replacement: "")
        case .deleteRange:
            guard length > 1 else {
                return GeneratedEdit(operation: operation, range: NSRange(location: 0, length: length), replacement: "")
            }
            let start = safeLocation()
            let span = min(rng.next(below: 8) + 1, length - start)
            return GeneratedEdit(operation: operation, range: ns.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: span)), replacement: "")
        case .replaceRange:
            guard length > 1 else {
                return GeneratedEdit(operation: operation, range: NSRange(location: 0, length: length), replacement: "y")
            }
            let start = safeLocation()
            let span = min(rng.next(below: 5) + 1, length - start)
            return GeneratedEdit(operation: operation, range: ns.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: span)), replacement: "replaced")
        case .insertAtDocumentStart:
            return GeneratedEdit(operation: operation, range: NSRange(location: 0, length: 0), replacement: "# new\n\n")
        case .insertAtDocumentEnd:
            return GeneratedEdit(operation: operation, range: NSRange(location: length, length: 0), replacement: "\ntail\n")
        }
    }

    static func apply(_ edit: GeneratedEdit, to source: String) -> String {
        let mutable = NSMutableString(string: source)
        mutable.replaceCharacters(in: edit.range, with: edit.replacement)
        return mutable as String
    }
}
