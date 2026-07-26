//
//  EditorUpdateOrigin.swift
//  Markdown Editor
//

import Foundation

/// Why an AppKit text/selection callback is firing.
///
/// // REQ-083/084; ARC-013: only native user input closes typing groups.
nonisolated enum EditorUpdateOrigin: Sendable, Equatable {
    case nativeUserInput
    case programmaticPresentation
    case selectionRestoration
    case modeRestoration
    case history
    case composition
}

/// Scoped origin for the duration of a programmatic view mutation.
///
/// Restores the previous origin with `defer` so nested callbacks keep the correct meaning.
@MainActor
final class EditorUpdateOriginScope {
    private(set) var current: EditorUpdateOrigin = .nativeUserInput
    private var stack: [EditorUpdateOrigin] = []

    @discardableResult
    func push(_ origin: EditorUpdateOrigin) -> EditorUpdateOrigin {
        stack.append(current)
        current = origin
        return origin
    }

    func pop() {
        current = stack.popLast() ?? .nativeUserInput
    }

    func with<T>(_ origin: EditorUpdateOrigin, _ body: () -> T) -> T {
        push(origin)
        defer { pop() }
        return body()
    }
}
