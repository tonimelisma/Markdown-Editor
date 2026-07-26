//
//  EditorModeState.swift
//  Markdown Editor
//

import CoreGraphics
import Foundation

/// Session-owned Source mode selection and scroll.
///
/// // REQ-052/086; ARC-002: sole typed owner per mode — no parallel view-state model.
nonisolated struct SourceModeState: Sendable, Equatable {
    var selection: SourceSelection
    var scrollOffset: CGPoint

    init(
        selection: SourceSelection = SourceSelection(utf16: NSRange(location: 0, length: 0)),
        scrollOffset: CGPoint = .zero
    ) {
        self.selection = selection
        self.scrollOffset = scrollOffset
    }
}

/// Whether WYSIWYG may accept edits against a current presentation.
///
/// // REQ-093; ARC-004: stale rich content is never editable.
nonisolated enum WYSIWYGAvailability: Sendable, Equatable {
    case waitingForCurrentProjection(SourceRevision)
    case editable(PresentationSnapshot.ID)
}

/// Session-owned WYSIWYG mode selection, scroll, and availability.
///
/// // REQ-052/086/093; ARC-002/004: selection is optional until a current snapshot exists.
nonisolated struct WYSIWYGModeState: Sendable, Equatable {
    var selection: ProjectionSelection?
    var scrollOffset: CGPoint
    var availability: WYSIWYGAvailability

    init(
        selection: ProjectionSelection? = nil,
        scrollOffset: CGPoint = .zero,
        availability: WYSIWYGAvailability = .waitingForCurrentProjection(SourceRevision(value: 0))
    ) {
        self.selection = selection
        self.scrollOffset = scrollOffset
        self.availability = availability
    }
}
