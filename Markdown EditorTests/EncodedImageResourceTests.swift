//
//  EncodedImageResourceTests.swift
//  Markdown EditorTests
//

import Foundation
import Testing
@testable import Markdown_Editor

struct EncodedImageResourceTests {
}

/// The accepted-extension set has one owner, derived from the representation enum.
///
/// // Validates: REQ-061, REQ-063 — vision.md names exactly PNG, JPEG, GIF, HEIC and HEIF, and before
/// COR-92 that list appeared verbatim as an array or `Set` in six places across five files, none
/// derived from `ImageRepresentation`. This is the closed-set guard: a new representation reddens
/// the table below until someone states its extension.
struct AcceptedImageExtensionTests {

    /// Every representation contributes its canonical extension, and nothing else appears.
    @Test func acceptedExtensionsAreDerivedFromTheRepresentations() {
        #expect(!ImageRepresentation.allCases.isEmpty)
        for representation in ImageRepresentation.allCases {
            #expect(
                ImageRepresentation.acceptedExtensions.contains(representation.canonicalExtension),
                "\(representation) contributes no accepted extension"
            )
        }
        // `jpeg` is the one alias: a second spelling of an existing representation, not a format.
        let aliases = ImageRepresentation.acceptedExtensions
            .subtracting(ImageRepresentation.allCases.map(\.canonicalExtension))
        #expect(aliases == ["jpeg"], "unexpected extension aliases: \(aliases.sorted())")
    }

    /// The mapping is total over the accepted set and rejects everything else, so no caller needs
    /// its own switch.
    @Test func everyAcceptedExtensionNamesARepresentation() {
        for ext in ImageRepresentation.acceptedExtensions {
            #expect(ImageRepresentation.fromExtension(ext) != nil, "\(ext) maps to no representation")
            #expect(
                ImageRepresentation.fromExtension(ext.uppercased()) != nil,
                "\(ext) is case-sensitive, so a .PNG file would be rejected"
            )
        }
        for ext in ["", "txt", "webp", "bmp", "tiff", "svg", "pdf"] {
            #expect(ImageRepresentation.fromExtension(ext) == nil, "\(ext) was accepted")
            #expect(!ImageRepresentation.acceptedExtensions.contains(ext), "\(ext) is in the set")
        }
    }

    /// Both spellings of JPEG resolve to the same representation — the property the deleted
    /// per-caller switches each had to restate.
    @Test func bothJPEGSpellingsResolveToOneRepresentation() {
        #expect(ImageRepresentation.fromExtension("jpg") == .jpeg)
        #expect(ImageRepresentation.fromExtension("jpeg") == .jpeg)
        #expect(ImageRepresentation.jpeg.canonicalExtension == "jpg")
    }
}
