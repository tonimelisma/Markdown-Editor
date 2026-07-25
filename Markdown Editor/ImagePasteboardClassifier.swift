//
//  ImagePasteboardClassifier.swift
//  Markdown Editor
//

import AppKit
import UniformTypeIdentifiers
import ImageIO

// REQ-060/063/064: classify pasteboard/drag payloads into immutable placement items
// immediately (avoid stale NSPasteboardItem lifetime).

nonisolated enum PasteClassification: Sendable {
    case images([ImagePlacementItem])
    case fallthroughToNativeText
    case unsupported
}

enum ImagePasteboardClassifier {
    // REQ-064: mixed meaningful text + image → native text paste.
    static func classifyPasteboard(_ pasteboard: NSPasteboard) -> PasteClassification {
        // Snapshot strings first.
        let plain = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMeaningfulText = !(plain?.isEmpty ?? true)

        var items: [ImagePlacementItem] = []

        // File URLs
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] {
            for url in urls {
                if let item = itemFromFileURL(url) {
                    items.append(item)
                } else if isImageURLClaim(url) {
                    return .unsupported
                }
            }
        }

        // Bitmap TIFF / PNG paste without file
        if items.isEmpty,
           let tiff = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            if let png = pngData(fromPasteboardImageData: tiff) {
                items.append(ImagePlacementItem(payload: .bitmapPNG(png, providerName: "image.png")))
            } else {
                return .unsupported
            }
        }

        if !items.isEmpty {
            if hasMeaningfulText {
                return .fallthroughToNativeText
            }
            return .images(items)
        }

        if hasMeaningfulText {
            return .fallthroughToNativeText
        }
        return .fallthroughToNativeText
    }

    static func classifyDragInfo(_ info: NSDraggingInfo) -> PasteClassification {
        let pb = info.draggingPasteboard
        return classifyPasteboard(pb)
    }

    static func itemFromFileURL(_ url: URL) -> ImagePlacementItem? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return nil
        }
        // Reject symlinks as sources for safety (REQ-077).
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard ImageAssetPolicy.detectRepresentation(from: data) != nil else { return nil }
        return ImagePlacementItem(payload: .fileBytes(data, providerName: url.lastPathComponent))
    }

    private static func isImageURLClaim(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp"].contains(ext)
    }

    private static func pngData(fromPasteboardImageData data: Data) -> Data? {
        if ImageAssetPolicy.detectRepresentation(from: data) == .png {
            return data
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return try? ImageAssetPolicy.encodePNG(from: image)
    }
}
