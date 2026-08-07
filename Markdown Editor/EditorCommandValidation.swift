//
//  EditorCommandValidation.swift
//  Markdown Editor
//

import Foundation

nonisolated enum EditorCommandDisabledReason: Equatable, Sendable {
    case noDocument
    case noSelection
    case unavailablePresentation
    case detached
    case staleSelection
}

nonisolated enum EditorCommandAvailability: Equatable, Sendable {
    case enabled
    case disabled(EditorCommandDisabledReason)

    var isEnabled: Bool {
        if case .enabled = self { return true }
        return false
    }
}
