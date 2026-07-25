//
//  ImagePasteboardClassifier.swift
//  Markdown Editor
//

import AppKit
import UniformTypeIdentifiers

// REQ-060/063/064: classify pasteboard/drag into immutable claims.
// Main actor does NOT read file bytes or run Image I/O (ADR-0012).

nonisolated enum PasteClassification: Sendable {
    case images([ImageClaim])
    case fallthroughToNativeText
    case unsupported
}

enum ImagePasteboardClassifier {
    // REQ-064: mixed meaningful text + image → native text paste.
    static func classifyPasteboard(_ pasteboard: NSPasteboard) -> PasteClassification {
        let plain = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMeaningfulText = !(plain?.isEmpty ?? true)

        var claims: [ImageClaim] = []

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] {
            for url in urls {
                if isObviousImageURLClaim(url) {
                    claims.append(.fileURL(url, providerName: url.lastPathComponent, declaredType: nil))
                } else if isUnsupportedImageExtension(url) {
                    return .unsupported
                }
                // Non-image URLs: ignore for image action (may fall through).
            }
        }

        if claims.isEmpty,
           let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            let declared: UTType? = pasteboard.data(forType: .png) != nil ? .png : .tiff
            claims.append(.bitmapData(data, providerName: "image.png", declaredType: declared))
        }

        if !claims.isEmpty {
            if hasMeaningfulText {
                return .fallthroughToNativeText
            }
            return .images(claims)
        }

        return .fallthroughToNativeText
    }

    static func classifyDragInfo(_ info: NSDraggingInfo) -> PasteClassification {
        classifyPasteboard(info.draggingPasteboard)
    }

    private static func isObviousImageURLClaim(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "heif"].contains(ext)
    }

    private static func isUnsupportedImageExtension(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["webp", "tif", "tiff", "bmp"].contains(ext)
    }
}
