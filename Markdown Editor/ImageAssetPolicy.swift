//
//  ImageAssetPolicy.swift
//  Markdown Editor
//

import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import CryptoKit

// REQ-061–068: pure representation detection, portable naming, and reference generation.
// Nonisolated value types so policy can run off the main actor (REQ-077).

nonisolated enum ImageRepresentation: String, Sendable, Hashable, CaseIterable {
    case png
    case jpeg
    case gif
    case heic
    case heif

    var canonicalExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .gif: return "gif"
        case .heic: return "heic"
        case .heif: return "heif"
        }
    }

    /// Every filename extension that names a supported representation, lowercased.
    ///
    /// // vision.md names exactly PNG, JPEG, GIF, HEIC and HEIF. Before COR-92 the literal
    /// // `["png", "jpg", "jpeg", "gif", "heic", "heif"]` appeared verbatim in four files and a
    /// // fifth time as a `Set`, none of them derived from this enum — the same defect COR-78
    /// // repaired for the `assets` directory name. Adding a representation now updates every
    /// // call site, and a typo in one copy is no longer possible.
    static let acceptedExtensions: Set<String> = {
        var extensions = Set(allCases.map(\.canonicalExtension))
        // `jpeg` is a second spelling of the same representation, not a sixth format, so it is
        // stated once here rather than in each caller's array.
        extensions.insert("jpeg")
        return extensions
    }()

    /// The representation a filename extension names, if any.
    static func fromExtension(_ ext: String) -> ImageRepresentation? {
        switch ext.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "gif": return .gif
        case "heic": return .heic
        case "heif": return .heif
        default: return nil
        }
    }

    static func fromImageIOType(_ type: String) -> ImageRepresentation? {
        switch type {
        case "public.png": return .png
        case "public.jpeg": return .jpeg
        case "com.compuserve.gif": return .gif
        case "public.heic": return .heic
        case "public.heif": return .heif
        default: return nil
        }
    }
}

nonisolated enum ImageAssetPolicyError: Error, Equatable, Sendable {
    case unsupportedOrCorrupt
    case typeMismatch
}

nonisolated enum ImageAssetPolicy {
    private static let maxStemLength = 64
    private static let reservedNames: Set<String> = {
        var names: Set<String> = ["con", "prn", "aux", "nul"]
        for i in 1...9 {
            names.insert("com\(i)")
            names.insert("lpt\(i)")
        }
        return names
    }()

    // REQ-061/063/077: detect representation from content via Image I/O, not extension alone.
    static func detectRepresentation(from data: Data) -> ImageRepresentation? {
        guard !data.isEmpty else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String? else {
            return nil
        }
        return ImageRepresentation.fromImageIOType(type)
    }

    static func detectRepresentation(at url: URL) -> ImageRepresentation? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
              let type = CGImageSourceGetType(source) as String? else {
            return nil
        }
        return ImageRepresentation.fromImageIOType(type)
    }

    /// Validates content is a supported image. Rejects unsupported claimed extensions.
    static func validate(
        data: Data,
        claimedExtension: String?
    ) throws -> ImageRepresentation {
        guard let detected = detectRepresentation(from: data) else {
            throw ImageAssetPolicyError.unsupportedOrCorrupt
        }
        if let claimed = claimedExtension?.lowercased(), !claimed.isEmpty {
            let normalized = claimed.hasPrefix(".") ? String(claimed.dropFirst()) : claimed
            let supportedClaims = ImageRepresentation.acceptedExtensions
            if !supportedClaims.contains(normalized) {
                throw ImageAssetPolicyError.typeMismatch
            }
        }
        return detected
    }

    // REQ-062: encode bitmap-only paste as PNG.
    static func encodePNG(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw ImageAssetPolicyError.unsupportedOrCorrupt
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ImageAssetPolicyError.unsupportedOrCorrupt
        }
        return data as Data
    }

    // REQ-066: portable lowercase ASCII filename stem.
    static func slug(from providerName: String?) -> String {
        let raw = providerName ?? ""
        var stem = ""
        var pendingHyphen = false
        for scalar in raw.lowercased().unicodeScalars {
            if (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 97 && scalar.value <= 122) {
                if pendingHyphen, !stem.isEmpty { stem.append("-") }
                pendingHyphen = false
                stem.append(Character(scalar))
            } else {
                pendingHyphen = !stem.isEmpty
            }
            if stem.count >= maxStemLength { break }
        }
        while stem.hasSuffix("-") { stem.removeLast() }
        if stem.isEmpty { stem = "image" }
        if reservedNames.contains(stem) { stem = "image-\(stem)" }
        while stem.hasSuffix(".") { stem.removeLast() }
        if stem.isEmpty { stem = "image" }
        return String(stem.prefix(maxStemLength))
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // REQ-067: choose a non-overwriting name with case-insensitive collision checks.
    static func chooseFilename(
        stem: String,
        representation: ImageRepresentation,
        sourceSHA256: String,
        existingNamesLowercased: Set<String>,
        bytesEqualAt: (String) -> Bool
    ) -> String {
        let ext = representation.canonicalExtension
        let primary = "\(stem).\(ext)"
        if !existingNamesLowercased.contains(primary.lowercased()) {
            return primary
        }
        if bytesEqualAt(primary) {
            return primary
        }
        var length = 12
        while length <= sourceSHA256.count {
            let suffix = String(sourceSHA256.prefix(length))
            let candidate = "\(stem)-\(suffix).\(ext)"
            if !existingNamesLowercased.contains(candidate.lowercased()) {
                return candidate
            }
            if bytesEqualAt(candidate) {
                return candidate
            }
            length += 4
        }
        var n = 0
        while true {
            let candidate = "\(stem)-\(sourceSHA256)-\(n).\(ext)"
            if !existingNamesLowercased.contains(candidate.lowercased()) {
                return candidate
            }
            if bytesEqualAt(candidate) {
                return candidate
            }
            n += 1
        }
    }

    // REQ-068: portable CommonMark image reference.
    static func markdownReference(filename: String) -> String {
        "![](assets/\(filename))"
    }

    static func markdownReferences(_ filenames: [String]) -> String {
        filenames.map { markdownReference(filename: $0) }.joined(separator: "\n")
    }
}
