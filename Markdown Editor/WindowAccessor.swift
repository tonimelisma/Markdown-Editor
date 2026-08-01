//
//  WindowAccessor.swift
//  Markdown Editor
//

import AppKit
import SwiftUI

/// Reports the window this view actually lives in.
///
/// // REQ-108; ARC-024: window-scoped ownership must come from the view hierarchy. Reading
/// `NSApp.keyWindow` during appearance is ambient — while a second document is opening, the key
/// window may still be the first one, which would bind a command controller and install a
/// toolbar on the wrong document's window.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        WindowReportingView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowReportingView: NSView {
    private let onResolve: (NSWindow) -> Void

    init(onResolve: @escaping (NSWindow) -> Void) {
        self.onResolve = onResolve
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        onResolve(window)
    }
}
