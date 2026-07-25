//
//  CanonicalAssetReferenceScanner.swift
//  Markdown Editor
//

import Foundation

// REQ-076: source-derived canonical assets/ reference scan (restart-independent).

nonisolated struct CanonicalAssetReference: Equatable, Sendable {
    let filename: String
    let relativePath: String // assets/<filename>
}

nonisolated enum CanonicalAssetReferenceScanner {
    private static let portableExt = #"(?:png|jpg|gif|heic|heif)"#
    private static let pattern = try! NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\((assets/([A-Za-z0-9._-]+\."# + portableExt + #"))\)"#
    )

    static func scan(_ source: String) -> [CanonicalAssetReference] {
        let ns = source as NSString
        let full = NSRange(location: 0, length: ns.length)
        let excluded = excludedRanges(in: source)

        var results: [CanonicalAssetReference] = []
        pattern.enumerateMatches(in: source, options: [], range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 4 else { return }
            let matchRange = match.range
            // Escaped image: odd number of backslashes immediately before '!'
            if isEscapedImage(in: ns, at: matchRange.location) { return }
            if excluded.contains(where: { NSIntersectionRange($0, matchRange).length > 0 }) {
                return
            }
            let rel = ns.substring(with: match.range(at: 2))
            let filename = ns.substring(with: match.range(at: 3))
            results.append(CanonicalAssetReference(filename: filename, relativePath: rel))
        }
        return results
    }

    /// Returns true when any scanned reference resolved under `oldParent` but not under `newParent`.
    static func hasBrokenReferences(
        source: String,
        oldParent: URL,
        newParent: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> Bool {
        let refs = scan(source)
        for ref in refs {
            let oldURL = oldParent.appendingPathComponent(ref.relativePath)
            let newURL = newParent.appendingPathComponent(ref.relativePath)
            if fileExists(oldURL) && !fileExists(newURL) {
                return true
            }
        }
        return false
    }

    private static func isEscapedImage(in ns: NSString, at location: Int) -> Bool {
        var i = location - 1
        var count = 0
        while i >= 0, ns.character(at: i) == UInt16(UnicodeScalar("\\").value) {
            count += 1
            i -= 1
        }
        return count % 2 == 1
    }

    /// Exclude fenced code, indented code blocks, and code spans (focused CommonMark-aware).
    private static func excludedRanges(in source: String) -> [NSRange] {
        let ns = source as NSString
        var ranges: [NSRange] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        var offset = 0
        var inFence = false
        var fenceMarker = ""

        for lineSub in lines {
            let line = String(lineSub)
            let lineLen = (line as NSString).length
            let lineRange = NSRange(location: offset, length: lineLen)

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inFence {
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                    inFence = true
                    fenceMarker = String(trimmed.prefix(3))
                    ranges.append(lineRange)
                } else if line.hasPrefix("    ") || line.hasPrefix("\t") {
                    ranges.append(lineRange)
                } else {
                    ranges.append(contentsOf: codeSpanRanges(in: line, base: offset))
                }
            } else {
                ranges.append(lineRange)
                if trimmed.hasPrefix(fenceMarker) {
                    inFence = false
                    fenceMarker = ""
                }
            }
            offset += lineLen + 1 // + newline
        }

        // Also whole-document backtick spans that cross simple cases on single lines already covered.
        _ = ns
        return ranges
    }

    private static func codeSpanRanges(in line: String, base: Int) -> [NSRange] {
        let ns = line as NSString
        var ranges: [NSRange] = []
        var i = 0
        let len = ns.length
        while i < len {
            if ns.character(at: i) == UInt16(UnicodeScalar("`").value) {
                var open = 1
                var j = i + 1
                while j < len, ns.character(at: j) == UInt16(UnicodeScalar("`").value) {
                    open += 1
                    j += 1
                }
                // Find matching close of same length
                var k = j
                var found: Int?
                while k < len {
                    if ns.character(at: k) == UInt16(UnicodeScalar("`").value) {
                        var close = 1
                        var m = k + 1
                        while m < len, ns.character(at: m) == UInt16(UnicodeScalar("`").value) {
                            close += 1
                            m += 1
                        }
                        if close == open {
                            found = m
                            break
                        }
                        k = m
                    } else {
                        k += 1
                    }
                }
                if let end = found {
                    ranges.append(NSRange(location: base + i, length: end - i))
                    i = end
                    continue
                }
            }
            i += 1
        }
        return ranges
    }
}
