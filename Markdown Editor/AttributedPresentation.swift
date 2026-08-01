//
//  AttributedPresentation.swift
//  Markdown Editor
//

import AppKit

/// Main-actor result of turning an immutable semantic projection into editable TextKit storage.
@MainActor
struct AttributedPresentation {
    let attributed: NSAttributedString
    let attachmentNodes: [Int: MarkdownNodeID]
}
