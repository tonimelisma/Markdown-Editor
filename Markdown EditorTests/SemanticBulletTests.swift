import Foundation
import Testing
@testable import Markdown_Editor

struct SemanticBulletTests {
    // Validates: REQ-054, REQ-056, REQ-107 — unordered list source spelling does not leak into the WYSIWYG
    // display, while the source remains available to the inverse mapping.
    @Test func unorderedListsRenderTheSameBulletForEverySourceSpelling() {
        let rendered = ["-", "*", "+"].compactMap { marker -> String? in
            let source = "\(marker) alpha\n\(marker) beta\n"
            guard case .success(let tree) = MarkdownParser.parse(source, sourceVersion: 1) else { return nil }
            let model = MarkdownProjectionModel.build(
                tree: tree,
                index: MarkdownSourceIndex(source: source, sourceVersion: 1)
            )
            return model.renderedString
        }
        #expect(rendered.count == 3)
        #expect(Set(rendered).count == 1)
        #expect(rendered.first == "• alpha\n• beta\n")
    }

    // Validates: REQ-054, REQ-057 — marker source boundaries remain tied to the original spelling.
    @Test func editingAListItemPreservesItsSourceMarkerSpelling() {
        let source = "* alpha\n"
        guard case .success(let tree) = MarkdownParser.parse(source, sourceVersion: 1) else {
            Issue.record("parse failed")
            return
        }
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: source, sourceVersion: 1)
        )
        guard let marker = model.listMarkers.first else {
            Issue.record("missing marker")
            return
        }
        #expect(marker.text == "• ")
        guard case .synthetic(_, .listMarker, .atSourceBoundaries(let before, _)) = model.segments.first else {
            Issue.record("marker is not an exact source-boundary atom")
            return
        }
        let original = (source as NSString).substring(with: NSRange(location: before, length: 1))
        #expect(original == "*")
    }

    // Validates: REQ-054, REQ-107 — nesting is a semantic visual distinction.
    @Test func nestedBulletsUseDistinctGlyphsPerDepth() {
        #expect(MarkdownTypography.listMarkerGlyphs == ["•", "◦", "▪"])
    }
}
