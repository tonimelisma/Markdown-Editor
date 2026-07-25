//
//  PastePolicy.swift
//  Markdown Editor
//

import AppKit

/// Ordinary text paste prefers plain-text representation — never infers Markdown from RTF/HTML.
///
/// // REQ-059/084: plain-text paste policy; COR-02 image classification unchanged.
enum PastePolicy {
    static func plainText(from pasteboard: NSPasteboard) -> String? {
        if let plain = pasteboard.string(forType: .string) {
            return plain
        }
        // Fall back through public.utf8-plain-text if present.
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.utf8-plain-text")),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return nil
    }

    /// Returns true when the pasteboard offers rich representations that must be ignored for text paste.
    static func offersRichText(on pasteboard: NSPasteboard) -> Bool {
        let types = Set(pasteboard.types ?? [])
        return types.contains(.rtf)
            || types.contains(.rtfd)
            || types.contains(.html)
            || types.contains(NSPasteboard.PasteboardType("public.html"))
    }
}
