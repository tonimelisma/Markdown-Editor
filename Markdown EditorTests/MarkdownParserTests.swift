//
//  MarkdownParserTests.swift
//  Markdown EditorTests
//

import XCTest
@testable import Markdown_Editor

final class MarkdownParserTests: XCTestCase {
    // Verifies: REQ-054
    func testPinnedRevisionAndExactExtensions() {
        XCTAssertEqual(MarkdownParser.pinnedRevision, "5d9bdaa4228b381639fff09403e39a04926e2dbe")
        XCTAssertEqual(
            MarkdownParser.enabledExtensions.sorted(),
            ["autolink", "strikethrough", "table", "tagfilter", "tasklist"]
        )
        // Double-tilde option set; smart punctuation not set.
        XCTAssertNotEqual(MarkdownParser.parserOptions & Int32(1 << 14), 0) // STRIKETHROUGH_DOUBLE_TILDE
        XCTAssertEqual(MarkdownParser.parserOptions & Int32(1 << 10), 0) // SMART
        XCTAssertEqual(MarkdownParser.parserOptions & Int32(1 << 20), 0) // TABLE_SPANS
    }

    // Verifies: REQ-054
    func testParsesCoreConstructsIntoValueAST() throws {
        let source = """
        # Hello
        **bold** and *italic* and ~~strike~~ and `code`
        - [x] done
        - [ ] todo
        <https://example.com>

        | a | b |
        | - | - |
        | 1 | 2 |

        <div>raw</div>
        """
        let tree = try XCTUnwrap(MarkdownParser.parse(source, sourceVersion: 1).get())
        XCTAssertEqual(tree.sourceVersion, 1)
        XCTAssertTrue(contains(tree.root) { if case .heading(1) = $0.kind { return true }; return false })
        XCTAssertTrue(contains(tree.root) { if case .strong = $0.kind { return true }; return false })
        XCTAssertTrue(contains(tree.root) { if case .emphasis = $0.kind { return true }; return false })
        XCTAssertTrue(contains(tree.root) { if case .strikethrough = $0.kind { return true }; return false })
        XCTAssertTrue(contains(tree.root) { if case .item(true) = $0.kind { return true }; return false })
        XCTAssertTrue(contains(tree.root) { if case .item(false) = $0.kind { return true }; return false })
        XCTAssertTrue(contains(tree.root) { if case .table = $0.kind { return true }; return false })
        XCTAssertTrue(contains(tree.root) { if case .htmlBlock = $0.kind { return true }; return false })
    }

    // Verifies: REQ-054 — single tilde is not strikethrough under formal GFM.
    func testSingleTildeIsNotStrikethrough() throws {
        let tree = try XCTUnwrap(MarkdownParser.parse("a ~b~ c", sourceVersion: 0).get())
        XCTAssertFalse(contains(tree.root) { if case .strikethrough = $0.kind { return true }; return false })
    }

    // Verifies: REQ-054
    func testFormalGFMSpecSuiteHTMLConformance() throws {
        let url = try XCTUnwrap(Bundle(for: MarkdownParserTests.self).url(forResource: "gfm-spec", withExtension: "txt", subdirectory: "Fixtures")
            ?? fixtureURL("gfm-spec.txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let examples = Self.parseSpecExamples(text)
        XCTAssertGreaterThanOrEqual(examples.count, 600, "expected formal GFM examples")

        var failures: [(Int, String)] = []
        for example in examples {
            switch MarkdownParser.renderHTML(example.markdown, extensions: example.extensions) {
            case .success(let html):
                let normalizedGot = Self.normalizeHTML(html)
                let normalizedWant = Self.normalizeHTML(example.html)
                if normalizedGot != normalizedWant {
                    failures.append((example.number, "got:\n\(normalizedGot)\nwant:\n\(normalizedWant)"))
                }
            case .failure(let err):
                failures.append((example.number, "parse failure \(err)"))
            }
        }
        if !failures.isEmpty {
            let sample = failures.prefix(5).map { "example \($0.0): \($0.1)" }.joined(separator: "\n---\n")
            XCTFail("\(failures.count)/\(examples.count) formal-GFM examples failed. First failures:\n\(sample)")
        }
    }

    // Verifies: REQ-054
    func testFormalGFMExtensionSuiteHTMLConformance() throws {
        let url = try XCTUnwrap(
            Bundle(for: MarkdownParserTests.self).url(forResource: "gfm-extensions", withExtension: "txt", subdirectory: "Fixtures")
            ?? fixtureURL("gfm-extensions.txt")
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        let examples = Self.parseSpecExamples(text)
        // extensions.txt is run with all formal extensions enabled globally.
        // Skip footnotes, IGNORE, and single-tilde strikethrough (not formal GFM).
        let skipped = Set([17, 18, 20, 23, 24, 25])
        let relevant = examples.filter { example in
            guard !skipped.contains(example.number) else { return false }
            return example.html.trimmingCharacters(in: .whitespacesAndNewlines) != "<IGNORE>"
        }
        XCTAssertGreaterThanOrEqual(relevant.count, 15)
        var failures: [(Int, String)] = []
        for example in relevant {
            switch MarkdownParser.renderHTML(example.markdown, extensions: MarkdownParser.enabledExtensions) {
            case .success(let html):
                if Self.normalizeHTML(html) != Self.normalizeHTML(example.html) {
                    failures.append((example.number, "mismatch"))
                }
            case .failure(let err):
                failures.append((example.number, "\(err)"))
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count)/\(relevant.count) formal extension examples failed: \(failures.prefix(8))")
    }

    // Verifies: REQ-054
    func testPathologicalInputsDoNotCrash() throws {
        let url = try XCTUnwrap(
            Bundle(for: MarkdownParserTests.self).url(forResource: "pathological-scaled", withExtension: "json", subdirectory: "Fixtures")
            ?? fixtureURL("pathological-scaled.json")
        )
        let data = try Data(contentsOf: url)
        let cases = try JSONDecoder().decode([PathologicalCase].self, from: data)
        XCTAssertEqual(cases.count, 21)
        for item in cases {
            // Pathological suite validates the C parser/render path (not full Swift AST materialization).
            let html = MarkdownParser.renderHTML(item.input)
            XCTAssertNotNil(html.get(), "\(item.name) failed: \(html)")
        }
    }

    // Verifies: REQ-054 — license attribution present.
    func testCmarkLicenseAttributionFileExists() {
        let repoLicense = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Markdown Editor/Licenses/cmark-gfm-COPYING.txt")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: repoLicense.path),
            "cmark-gfm license attribution must be present in the app sources"
        )
        let contents = try? String(contentsOf: repoLicense, encoding: .utf8)
        XCTAssertTrue(contents?.contains("BSD") == true || contents?.contains("Copyright") == true)
    }

    // MARK: - Helpers

    private struct SpecExample {
        let number: Int
        let markdown: String
        let html: String
        let extensions: [String]
    }

    private struct PathologicalCase: Decodable {
        let name: String
        let input: String
    }

    private static func parseSpecExamples(_ text: String) -> [SpecExample] {
        let delimiter = String(repeating: "`", count: 32)
        var examples: [SpecExample] = []
        var number = 0
        var state = 0 // 0 text, 1 markdown, 2 html
        var extensions: [String] = []
        var markdownLines: [String] = []
        var htmlLines: [String] = []
        var skip = false

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix(delimiter + " example") {
                state = 1
                let rest = String(trimmed.dropFirst((delimiter + " example").count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                extensions = rest.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                skip = extensions.contains("disabled")
                extensions.removeAll { $0 == "disabled" }
                markdownLines = []
                htmlLines = []
            } else if trimmed == delimiter {
                if state != 0 {
                    number += 1
                    if !skip {
                        // Match cmark spec_tests.py: ''.join(lines) then replace → with tab.
                        var markdown = markdownLines.joined(separator: "\n")
                        if !markdownLines.isEmpty { markdown += "\n" }
                        markdown = markdown.replacingOccurrences(of: "→", with: "\t")
                        var html = htmlLines.joined(separator: "\n")
                        if !htmlLines.isEmpty { html += "\n" }
                        html = html.replacingOccurrences(of: "→", with: "\t")
                        examples.append(SpecExample(number: number, markdown: markdown, html: html, extensions: extensions))
                    }
                }
                state = 0
                extensions = []
                markdownLines = []
                htmlLines = []
                skip = false
            } else if trimmed == "." && state == 1 {
                state = 2
            } else if state == 1 {
                markdownLines.append(line)
            } else if state == 2 {
                htmlLines.append(line)
            }
        }
        return examples
    }

    private static func normalizeHTML(_ html: String) -> String {
        html
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func contains(_ node: MarkdownNode, where predicate: (MarkdownNode) -> Bool) -> Bool {
        if predicate(node) { return true }
        return node.children.contains { contains($0, where: predicate) }
    }

    private func fixtureURL(_ name: String) -> URL? {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: base.path) ? base : nil
    }
}
