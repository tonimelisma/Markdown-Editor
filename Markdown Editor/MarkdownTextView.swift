//
//  MarkdownTextView.swift
//  Markdown Editor
//

import SwiftUI
import AppKit

// REQ-010/011/012/040/046: the live-styled source editor. A TextKit 1 NSTextView (ADR-0008)
// wrapped for SwiftUI; highlighting computes off-main and applies on-main (ADR-0010).
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 (ADR-0008: usingTextLayoutManager false).
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true                          // REQ-011
        textView.font = context.coordinator.theme.baseFont
        // Preserve the user's exact bytes (INV-2): no smart quotes / dashes / replacement.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.usesFindBar = true                         // REQ-046
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.highlight()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        // Only push genuinely external changes; guard the delegate→binding→update loop.
        if textView.string != text {
            context.coordinator.isProgrammaticUpdate = true
            textView.string = text
            context.coordinator.isProgrammaticUpdate = false
            context.coordinator.highlight()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        let theme = MarkdownTheme()
        private let highlighter = MarkdownHighlighter()
        weak var textView: NSTextView?
        var isProgrammaticUpdate = false
        private var version = 0
        private var task: Task<Void, Never>?
        private let maxHighlightLength = 100_000   // size-threshold escape hatch (ADR-0010)
        /// True after we have suspended styling above the size cap; used to clear frozen attrs once.
        private var stylingSuspended = false

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate, let textView else { return }
            text.wrappedValue = textView.string        // INV-2: the string is the source of truth
            highlight(debounced: true)
        }

        // REQ-040/045: recompute styling off-main, coalesced by version, applied on-main.
        func highlight(debounced: Bool = false) {
            guard let textView else { return }
            version &+= 1
            let expectedVersion = version
            let snapshot = textView.string
            task?.cancel()

            // Above the threshold, suspend styling. Clear prior attributes once on the transition
            // so frozen highlighting does not linger; do not re-walk storage every keystroke.
            if snapshot.utf16.count > maxHighlightLength {
                if !stylingSuspended {
                    stylingSuspended = true
                    applyBaseAttributesOnly()
                }
                return
            }
            stylingSuspended = false
            task = Task { [weak self] in
                if debounced {
                    try? await Task.sleep(for: .milliseconds(120))
                    if Task.isCancelled { return }
                }
                guard let self else { return }
                let tokens: [Token]
                do {
                    tokens = try await self.highlighter.tokens(for: snapshot)
                } catch {
                    return  // cancelled or failed pass — discard
                }
                if Task.isCancelled { return }
                self.apply(tokens, expectedVersion: expectedVersion, expectedText: snapshot)
            }
        }

        private func applyBaseAttributesOnly() {
            guard let textView, let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes(theme.baseAttributes, range: full)
            storage.endEditing()
        }

        // REQ-040/041/043/047–051: style via NSTextStorage attributes — display only; the saved
        // STRING is never modified, so INV-2 holds. Applied outside processEditing (from
        // textDidChange) to avoid caret jumps, and batched in begin/endEditing.
        private func apply(_ tokens: [Token], expectedVersion: Int, expectedText: String) {
            guard expectedVersion == version,
                  let textView, textView.string == expectedText,
                  let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes(theme.baseAttributes, range: full)
            for token in tokens where NSMaxRange(token.range) <= full.length {
                storage.addAttributes(theme.attributes(for: token.style), range: token.range)
            }
            storage.endEditing()
        }
    }
}
