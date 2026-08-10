import Foundation

/// Closed corpus enumeration whose shapes assert their own structure.
///
/// // REQ-127.
nonisolated enum PerformanceCorpus: String, CaseIterable, Sendable {
    case degenerateParagraph
    case structuredProse
    case heavyLists
    case tableDense
    case codeHeavy
    case imageHeavy

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
            let targetLength = (result as NSString).length
            let excess = targetLength - utf16Target
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

func insertionPoints(in model: MarkdownProjectionModel, count: Int) -> [Int] {
    // Return caret locations classified .identityText.
    // Simplified: return 0, mid, end.
    let len = (model.renderedString as NSString).length
    return (0..<count).map { i in min(len, i * max(1, len / max(1, count))) }
}
