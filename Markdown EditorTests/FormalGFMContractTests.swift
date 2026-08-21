//
//  FormalGFMContractTests.swift
//  Markdown EditorTests
//

import Foundation
import Testing
@testable import Markdown_Editor

/// The manifest is deliberately data-driven: adding a formal construct without adding its
/// parser, source-style, projection, and range behavior fails this closed matrix.
struct FormalGFMContractTests {
    private struct Manifest: Decodable {
        let schemaVersion: Int
        let dialect: String
        let pinnedRevision: String
        let fixtures: [Fixture]
    }

    private struct Fixture: Decodable {
        let id: String
        let `class`: String
        let source: String
        let highlightStyle: String

        var unsupported: Bool { `class`.hasPrefix("unsupported.") || `class` == "malformed.image" }
    }

    // Verifies: REQ-047/054 — one pinned declaration and one manifest own the dialect contract.
    @Test func manifestMatchesClosedProductionDialect() throws {
        let manifest = try loadManifest()
        #expect(manifest.schemaVersion == 1)
        #expect(manifest.dialect == FormalGFMDialect.name)
        #expect(manifest.pinnedRevision == FormalGFMDialect.pinnedRevision)
        #expect(MarkdownParser.pinnedRevision == manifest.pinnedRevision)
        #expect(MarkdownParser.enabledExtensions == FormalGFMDialect.enabledExtensions)
        #expect(Set(FormalGFMDialect.enabledExtensions).isDisjoint(with: FormalGFMDialect.unsupportedWritingExtensions))
        #expect(manifest.fixtures.count >= 15)
    }

    // Verifies: REQ-047/048/049/050/053/054/055/056 — every declared fixture succeeds through
    // parse, source index, projection oracle, and source highlighter routes.
    @Test func everyFormalFixtureUsesAllProductionBoundaries() async throws {
        let manifest = try loadManifest()
        let highlighter = MarkdownHighlighter()

        for fixture in manifest.fixtures {
            let tree = try #require(MarkdownParser.parse(fixture.source, sourceVersion: 1).get())
            let index = MarkdownSourceIndex(source: fixture.source, sourceVersion: 1)
            let model = MarkdownProjectionModel.build(tree: tree, index: index)
            guard case .success = ProjectionOracle.validate(model: model, sourceUTF16Count: (fixture.source as NSString).length) else {
                Issue.record("projection oracle refused fixture \(fixture.id)")
                continue
            }

            assertNodeRanges(tree.root, index: index, fixtureID: fixture.id)
            assertSemanticClass(fixture, tree: tree.root)
            if fixture.unsupported {
                #expect(model.renderedString.contains(fixture.source.split(whereSeparator: \.isNewline).first.map(String.init) ?? fixture.source))
            }

            let tokens = try await highlighter.tokens(for: fixture.source)
            #expect(hasHighlight(fixture.highlightStyle, tokens: tokens))
            if fixture.unsupported {
                #expect(tokens.allSatisfy { $0.style != .strikethrough && $0.style != .table && $0.style != .taskMarker })
            }
        }
    }

    // Verifies: REQ-048/049 — formal double-tilde is semantic while single-tilde and writing
    // extension spellings remain literal source.
    @Test func unsupportedWritingExtensionsRemainLiteral() throws {
        let manifest = try loadManifest()
        for fixture in manifest.fixtures where fixture.unsupported {
            let tree = try #require(MarkdownParser.parse(fixture.source, sourceVersion: 1).get())
            #expect(!containsUnsupportedSemanticNode(tree.root))
        }
        let strike = try #require(MarkdownParser.parse("~~ok~~", sourceVersion: 1).get())
        #expect(contains(strike.root) { if case .strikethrough = $0.kind { return true }; return false })
    }

    // Verifies: REQ-050/055/056 — source-backed image ranges and delimiter-free visible text agree
    // with the original UTF-8 and UTF-16 coordinates.
    @Test func imageAndDelimiterRoundTripsAreExact() throws {
        let source = "![x](<a b>) and **bold** &amp; café 🐙\r\n"
        let tree = try #require(MarkdownParser.parse(source, sourceVersion: 7).get())
        let index = MarkdownSourceIndex(source: source, sourceVersion: 7)
        let image = try #require(first(tree.root) { if case .image = $0.kind { return true }; return false })
        let imageSource = try #require(index.substring(position: image.position).get())
        #expect(imageSource == "![x](<a b>)")

        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        #expect(!model.renderedString.contains("**"))
        #expect(!model.renderedString.contains("![x]"))
        #expect(model.renderedString.contains("bold"))
        #expect(model.renderedString.contains("&"))
        #expect(model.renderedString.contains("café 🐙"))
        #expect(MarkdownLiteralEncoder.encode(LiteralEncodeContext(
            intendedVisibleText: "a|b",
            precedingSourceCharacter: nil,
            followingSourceCharacter: nil,
            atLineStart: false,
            container: .tableCell,
            dialect: .formalGFM
        )) == .encoded("a\\|b"))
    }

    private func loadManifest() throws -> Manifest {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/formal-gfm-fixtures.json")
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
    }

    private func assertNodeRanges(_ node: MarkdownNode, index: MarkdownSourceIndex, fixtureID: String) {
        if node.position.isKnown {
            let utf8 = index.utf8Range(for: node.position)
            let utf16 = index.utf16Range(for: node.position)
            // cmark may report a link-like position for a disabled writing extension that has
            // no concrete source span; the contract is a typed refusal rather than a guess.
            let allowsTypedRefusal = fixtureID.hasPrefix("unsupported-")
            #expect(utf8.get() != nil || allowsTypedRefusal)
            #expect(utf16.get() != nil || allowsTypedRefusal)
            if case .success(let utf8Range) = utf8,
               case .success(let utf8Text) = index.substring(utf8: utf8Range),
               case .success(let utf16Range) = utf16,
               case .success(let utf16Text) = index.substring(utf16: utf16Range) {
                #expect(utf8Text == utf16Text)
            }
        }
        for child in node.children { assertNodeRanges(child, index: index, fixtureID: fixtureID) }
    }

    private func assertSemanticClass(_ fixture: Fixture, tree: MarkdownNode) {
        switch fixture.class {
        case "extension.strikethrough": #expect(contains(tree) { if case .strikethrough = $0.kind { return true }; return false })
        case "extension.table": #expect(contains(tree) { if case .table = $0.kind { return true }; return false })
        case "extension.tasklist": #expect(contains(tree) { if case .item(let checked) = $0.kind { return checked != nil }; return false })
        case "core.link-image": #expect(contains(tree) { if case .image = $0.kind { return true }; return false })
        case "core.raw-html": #expect(contains(tree) { if case .htmlBlock = $0.kind { return true }; if case .htmlInline = $0.kind { return true }; return false })
        case "core.code-span-fence": #expect(contains(tree) { if case .code = $0.kind { return true }; return false })
        default: break
        }
    }

    private func hasHighlight(_ style: String, tokens: [Token]) -> Bool {
        switch style {
        case "none": return true
        case "bold": return tokens.contains { $0.style == .bold }
        case "image": return tokens.contains { $0.style == .image }
        case "codeBlock": return tokens.contains { $0.style == .codeBlock }
        case "strikethrough": return tokens.contains { $0.style == .strikethrough }
        case "table": return tokens.contains { $0.style == .table }
        case "taskMarker": return tokens.contains { $0.style == .taskMarker }
        default: return false
        }
    }

    private func containsUnsupportedSemanticNode(_ node: MarkdownNode) -> Bool {
        if case .strikethrough = node.kind { return true }
        if case .item(let checked) = node.kind, checked != nil { return true }
        if case .table = node.kind { return true }
        return node.children.contains { containsUnsupportedSemanticNode($0) }
    }

    private func contains(_ node: MarkdownNode, where predicate: (MarkdownNode) -> Bool) -> Bool {
        if predicate(node) { return true }
        return node.children.contains { contains($0, where: predicate) }
    }

    private func first(_ node: MarkdownNode, where predicate: (MarkdownNode) -> Bool) -> MarkdownNode? {
        if predicate(node) { return node }
        for child in node.children {
            if let found = first(child, where: predicate) { return found }
        }
        return nil
    }
}
