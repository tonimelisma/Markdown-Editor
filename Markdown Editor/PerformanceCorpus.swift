import Foundation

/// Closed corpus enumeration whose shapes assert their own structure.
///
/// // REQ-127.
nonisolated enum PerformanceCorpus: String, CaseIterable, Codable, Sendable {
    case degenerateParagraph
    case structuredProse
    case heavyLists
    case tableDense
    case codeHeavy
    case imageHeavy

    /// Whether this shape is a **stress** case rather than a document anyone writes.
    ///
    /// // REQ-143: the interactive budget binds on shapes that represent real documents. The two
    /// // stress shapes below are deliberately denser than any real Markdown — `tableDense` is a
    /// // table row every 1.2 characters and `heavyLists` a list item every 4.3 — and they exist
    /// // to bound worst-case degradation, not to define interactive latency. `CLAUDE.md` §3
    /// // warns that a measurement describes only the input it was measured on; treating these as
    /// // the interactive contract is REQ-090's "corpus of one repeated word" error inverted.
    /// //
    /// // `degenerateParagraph` is degenerate in *length*, not density — 100,000 characters in one
    /// // block — and it meets the budget comfortably, so it stays inside the contract.
    var isStressShape: Bool {
        switch self {
        case .heavyLists, .tableDense: return true
        case .degenerateParagraph, .structuredProse, .codeHeavy, .imageHeavy: return false
        }
    }

    var minimumExpectedBlocks: Int {
        switch self {
        case .degenerateParagraph: return 1
        case .structuredProse: return 1000
        case .heavyLists: return 2000
        case .tableDense: return 800
        case .codeHeavy: return 800
        case .imageHeavy: return 1500
        }
    }

    func source(utf16Target: Int = 100_000) -> String {
        let unit: String
        switch self {
        case .degenerateParagraph:
            unit = "word "
        case .structuredProse:
            unit = "## Heading\n\nParagraph with **strong**, *emphasis*, `code` and [link](https://example.com).\n\n"
        case .heavyLists:
            unit = "- item\n  - nested\n    - deeper\n- [ ] task\n1. ordered\n\n"
        case .tableDense:
            unit = "| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n\n"
        case .codeHeavy:
            unit = "```swift\nlet x = 1\nlet y = 2\nlet z = x + y\n```\n\n"
        case .imageHeavy:
            unit = "![alt](assets/sample.png)\n\nParagraph.\n\n"
        }
        var result = ""
        result.reserveCapacity(utf16Target + unit.utf16.count)
        while (result as NSString).length < utf16Target {
            result += unit
        }
        // Truncate on unit boundary, never mid-unit.
        if (result as NSString).length > utf16Target {
            // Find last unit boundary within 5% tolerance.
            // Remove excess by trimming whole units from end until within 5%.
            var trimmed = result
            while (trimmed as NSString).length > Int(Double(utf16Target) * 1.05) {
                if let range = trimmed.range(of: unit, options: .backwards), range.upperBound == trimmed.endIndex {
                    trimmed.removeSubrange(range)
                } else {
                    break
                }
            }
            // If still over, truncate to target but ensure we end on unit boundary by trimming to last unit.
            if (trimmed as NSString).length > utf16Target {
                if let lastUnit = trimmed.range(of: unit, options: .backwards) {
                    trimmed = String(trimmed[..<lastUnit.upperBound])
                    // If still over, keep trimming one unit.
                    while (trimmed as NSString).length > utf16Target + Int(Double(utf16Target) * 0.05) {
                        if let r = trimmed.range(of: unit, options: .backwards) {
                            trimmed.removeSubrange(r)
                        } else { break }
                    }
                }
            }
            result = trimmed
        }
        // Ensure within 5% of target.
        assert(abs((result as NSString).length - utf16Target) <= Int(Double(utf16Target) * 0.05) + unit.utf16.count)
        return result
    }
}
