//
//  DiagnosticValue.swift
//  Markdown Editor
//

import Foundation

/// A value admissible in a diagnostic payload.
///
/// // REQ-089; ARC-016: there is deliberately no `String` case. Document text, replacement text,
/// // selected text, URLs, image descriptions, filenames, and paths are therefore not omitted by
/// // convention — they are unrepresentable. Adding a string case would defeat the invariant and
/// // is the one change this type must never accept.
nonisolated enum DiagnosticValue: Sendable, Equatable {
    case int(Int)
    case uint(UInt64)
    case double(Double)
    case bool(Bool)
    case symbol(DiagnosticSymbol)

    /// JSON fragment for this value. Symbols are drawn from a closed code-defined vocabulary,
    /// so the emitted text never originates from a document.
    var jsonFragment: String {
        switch self {
        case .int(let value): return String(value)
        case .uint(let value): return String(value)
        case .double(let value):
            guard value.isFinite else { return "null" }
            return String(format: "%.6f", value)
        case .bool(let value): return value ? "true" : "false"
        case .symbol(let symbol): return "\"\(symbol.rawValue)\""
        }
    }
}

/// The complete closed vocabulary of code-defined symbols a diagnostic payload may contain.
///
/// // REQ-089; ARC-016: every case is a compile-time literal written by this project.
nonisolated enum DiagnosticSymbol: String, Sendable, Equatable, CaseIterable {
    // Editor modes
    case source
    case wysiwyg

    // Update origins
    case nativeUserInput
    case programmaticPresentation
    case selectionRestoration
    case modeRestoration
    case history
    case composition

    // History directions
    case undo
    case redo

    // Source-edit refusals
    case staleVersion
    case invalidRange
    case conflict
    case contentMismatch

    // Document I/O failures
    case invalidUTF8
    case fileUnreadable
    case saveFailedOrCancelled

    // Semantic-edit refusals
    case stalePresentation
    case ambiguousSelection
    case unsupportedCommand
    case mappingFailure
    case unavailable
    case mixedDomain
    case crossCell
    case unprovable
    case invalidPresentationTransition

    // Reconciliation discard reasons
    case stale
    case parseFailure
    case oracleModel
    case oracleSnapshot
    case identityMismatch

    // Reconciliation violations
    case publication
    case liveStateCapture

    // Planner kinds
    case insertText
    case deleteBackward
    case toggleBold
    case toggleItalic
    case toggleStrikethrough
    case toggleInlineCode
    case setParagraph
    case setHeading
    case toggleOrderedList
    case toggleUnorderedList
    case toggleTaskList
    case toggleBlockQuote
    case toggleCodeBlock
    case setLink
    case toggleTask
    case replaceTableCell
    case insertImageMarkdown

    // Image-placement phases
    case idle
    case accepted
    case receivingPromises
    case awaitingSave
    case staging
    case publishing
    case committing
    case committed
    case cancelled
    case failed

    // Image-placement errors
    case busy
    case noDocumentURL
    case saveCancelled
    case saveFailed
    case documentMoved
    case unsafeDestination
    case unsupportedOrCorrupt
    case typeMismatch
    case writeFailed
    case promiseFailed
    case promiseTimedOut
    case nonRegularSource
    case parentChanged
    case nativeInputCallback
    case modeTransition
    case parseProjection
    case imageResolution
    case authoritativeApplication

    // Alert reasons with no natural ImagePlacementError equivalent
    case noInsertionTarget
    case insertionPointChanged

    // Alert severities
    case alertError
    case alertWarning
    case alertInfo
}
