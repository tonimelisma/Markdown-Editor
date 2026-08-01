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
        return CanonicalAssetReferences(values: refs)
    }

    static func parse(source: String, sourceVersion: UInt64) -> CanonicalAssetReferences {
        guard case .success(let tree) = MarkdownParser.parse(source, sourceVersion: sourceVersion) else {
            return CanonicalAssetReferences(values: [])
        }
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: source, sourceVersion: sourceVersion)
        )
        return from(model: model)
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
