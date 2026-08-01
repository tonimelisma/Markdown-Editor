//
//  CanonicalAssetReferences.swift
//  Markdown Editor
//

import Foundation

/// Image destinations copied from the pinned cmark-derived projection, never a regex scan.
nonisolated struct CanonicalAssetReference: Equatable, Sendable {
    let filename: String
    let relativePath: String
    let sourceRange: NSRange?
}

nonisolated struct CanonicalAssetReferences: Equatable, Sendable {
    let values: [CanonicalAssetReference]
    /// Source revision represented by this immutable parse product. Consumers that make a
    /// location-sensitive decision must wait for this to match the document's current source.
    let sourceVersion: UInt64

    init(values: [CanonicalAssetReference], sourceVersion: UInt64 = 0) {
        self.values = values
        self.sourceVersion = sourceVersion
    }

    static func from(model: MarkdownProjectionModel) -> CanonicalAssetReferences {
        let refs = model.attachments.compactMap { attachment -> CanonicalAssetReference? in
            guard case .image(let destination, _) = attachment.kind,
                  destination.hasPrefix("assets/"),
                  destination.count > "assets/".count else { return nil }
            let filename = String(destination.dropFirst("assets/".count))
            let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
            guard ["png", "jpg", "jpeg", "gif", "heic", "heif"].contains(ext),
                  !filename.contains("/") else { return nil }
            return CanonicalAssetReference(
                filename: filename,
                relativePath: destination,
                sourceRange: attachment.sourceUTF16Range
            )
        }
        return CanonicalAssetReferences(values: refs, sourceVersion: model.sourceVersion)
    }

    func hasBrokenReferences(
        oldParent: URL,
        newParent: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> Bool {
        values.contains { reference in
            let oldURL = oldParent.appendingPathComponent(reference.relativePath)
            let newURL = newParent.appendingPathComponent(reference.relativePath)
            return fileExists(oldURL) && !fileExists(newURL)
        }
    }
}
