//
//  EditorSelectionIntent.swift
//  Markdown Editor
//

import CoreGraphics
import Foundation

/// Domain of a selection intent — must match the active editor.
///
/// // REQ-052/086/087: wrong-domain intents refuse rather than guess.
nonisolated enum EditorCoordinateDomain: Sendable, Equatable {
    case source
    case wysiwyg
}

/// Typed selection intent that must resolve through the correct coordinate domain.
///
/// // REQ-052/086/087: wrong domain refuses; never clamps.
nonisolated struct EditorSelectionIntent: Sendable, Equatable {
    let domain: EditorCoordinateDomain
    let sourceVersion: UInt64
    let range: NSRange
    let affinity: SelectionAffinity

    func resolvedSourceRange(
        snapshot: SourceSnapshot,
        projection: MarkdownProjectionModel?
    ) -> CoordinateMappingResult {
        guard sourceVersion == snapshot.sourceVersion else {
            return .refused(.stale)
        }
        switch domain {
        case .source:
            let length = (snapshot.text as NSString).length
            guard range.location >= 0, NSMaxRange(range) <= length else {
                return .refused(.outOfBounds)
            }
            return .exact(range)
        case .wysiwyg:
            guard let projection, projection.sourceVersion == snapshot.sourceVersion else {
                return .refused(.stale)
            }
            return projection.coordinateMap.sourceRange(forProjection: range, affinity: affinity)
        }
    }
}

/// Mode-local chrome snapshot used by the persistent host and session.
nonisolated struct EditorViewState: Sendable, Equatable {
    var selection: NSRange = NSRange(location: 0, length: 0)
    var affinity: SelectionAffinity = .downstream
    var scrollOffset: CGPoint = .zero
    var acceptedSourceVersion: UInt64 = 0
}

/// Pure IME composition state for WYSIWYG.
///
/// // REQ-084: marked text stays transient until completion; stale refuses.
nonisolated struct CompositionState: Sendable, Equatable {
    var isComposing: Bool = false
    var markedRange: NSRange?
    var capturedSourceVersion: UInt64?
    var capturedSourceRange: NSRange?

    mutating func begin(sourceVersion: UInt64, sourceRange: NSRange, marked: NSRange) {
        isComposing = true
        capturedSourceVersion = sourceVersion
        capturedSourceRange = sourceRange
        markedRange = marked
    }

    mutating func update(marked: NSRange) {
        markedRange = marked
    }

    mutating func cancel() {
        self = CompositionState()
    }

    /// Returns captured mutation coordinates when composition finishes successfully.
    mutating func complete() -> (version: UInt64, range: NSRange)? {
        defer { self = CompositionState() }
        guard isComposing,
              let version = capturedSourceVersion,
              let range = capturedSourceRange else {
            return nil
        }
        return (version, range)
    }

    /// Stale composition when document revision advanced during IME.
    func isStale(relativeTo currentVersion: UInt64) -> Bool {
        guard let captured = capturedSourceVersion else { return false }
        return captured != currentVersion
    }
}
