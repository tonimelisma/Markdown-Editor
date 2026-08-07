//
//  ProjectionAtom.swift
//  Markdown Editor
//

import Foundation

/// Concrete inverse for atomic source representations (entities, escapes, markers).
///
/// // REQ-087/092; ARC-007/008: editable only when decoder and encoder are proven.
nonisolated enum AtomicRepresentationKind: Sendable, Equatable {
    case htmlEntity
    case backslashEscape
    case taskMarker
    case softBreak
    case hardBreak
    case normalizedCodeBlock
}

nonisolated struct IdentityAtom: Sendable, Equatable {
    let projection: NSRange
    let source: NSRange
    let insertionBefore: Int
    let insertionAfter: Int
}

nonisolated struct AtomicSourceAtom: Sendable, Equatable {
    let kind: AtomicRepresentationKind
    let projection: NSRange
    let source: NSRange
    let insertionBefore: Int
    let insertionAfter: Int
    let decodedText: String
}

nonisolated struct SyntheticAtom: Sendable, Equatable {
    let projection: NSRange
    let kind: SyntheticKind
    let insertion: SyntheticInsertionPolicy
}

nonisolated struct UneditableAtom: Sendable, Equatable {
    let projection: NSRange
    let reason: ProjectionRefusal
}

/// One coverage unit of a presented WYSIWYG snapshot.
///
/// // REQ-054–056/087; ARC-003/007: identity, atomic, synthetic, or uneditable — never guessed.
nonisolated enum ProjectionAtom: Sendable, Equatable {
    case identity(IdentityAtom)
    case atomic(AtomicSourceAtom)
    case synthetic(SyntheticAtom)
    case uneditable(UneditableAtom)

    var projectionRange: NSRange {
        switch self {
        case .identity(let atom): return atom.projection
        case .atomic(let atom): return atom.projection
        case .synthetic(let atom): return atom.projection
        case .uneditable(let atom): return atom.projection
        }
    }

    /// Build typed atoms from concrete source and rendered slices.
    static func from(
        segments: [ProjectionSegment],
        sourceText: String,
        renderedText: String
    ) -> [ProjectionAtom] {
        let sourceString = sourceText as NSString
        let renderedString = renderedText as NSString
        return segments.flatMap { segment -> [ProjectionAtom] in
            switch segment {
            case .source(let projection, let source, let before, let after):
                guard NSMaxRange(projection) <= renderedString.length,
                      NSMaxRange(source) <= sourceString.length else {
                    return [.uneditable(UneditableAtom(projection: projection, reason: .outOfBounds))]
                }
                let sourceSpelling = sourceString.substring(with: source)
                let visible = renderedString.substring(with: projection)
                if sourceSpelling == visible {
                    return [
                        .identity(
                            IdentityAtom(
                                projection: projection,
                                source: source,
                                insertionBefore: before,
                                insertionAfter: after
                            )
                        )
                    ]
                }
                return concreteAtoms(
                    projectionLocation: projection.location,
                    sourceLocation: source.location,
                    visible: visible,
                    source: sourceSpelling
                ) ?? [
                    .uneditable(UneditableAtom(projection: projection, reason: .unsupported))
                ]
            case .synthetic(let projection, let kind, let insertion):
                return [.synthetic(
                    SyntheticAtom(projection: projection, kind: kind, insertion: insertion)
                )]
            case .literalFallback(let projection, let source):
                guard projection.length == source.length else {
                    return [.uneditable(
                        UneditableAtom(projection: projection, reason: .unsupported)
                    )]
                }
                return [.identity(
                    IdentityAtom(
                        projection: projection,
                        source: source,
                        insertionBefore: source.location,
                        insertionAfter: NSMaxRange(source)
                    )
                )]
            case .uneditable(let projection, let reason):
                return [.uneditable(UneditableAtom(projection: projection, reason: reason))]
            }
        }
    }

    static func concreteAtoms(
        projectionLocation: Int,
        sourceLocation: Int,
        visible: String,
        source: String
    ) -> [ProjectionAtom]? {
        let visibleText = visible as NSString
        let sourceText = source as NSString
        var visibleOffset = 0
        var sourceOffset = 0
        var atoms: [ProjectionAtom] = []

        while visibleOffset < visibleText.length {
            let visibleRange = visibleText.rangeOfComposedCharacterSequence(at: visibleOffset)
            let visibleCharacter = visibleText.substring(with: visibleRange)

            if sourceOffset + 1 < sourceText.length,
               sourceText.character(at: sourceOffset) == 0x5C {
                let escapedRange = sourceText.rangeOfComposedCharacterSequence(at: sourceOffset + 1)
                if sourceText.substring(with: escapedRange) == visibleCharacter {
                    let atomSource = NSRange(
                        location: sourceLocation + sourceOffset,
                        length: 1 + escapedRange.length
                    )
                    atoms.append(
                        .atomic(
                            AtomicSourceAtom(
                                kind: .backslashEscape,
                                projection: NSRange(
                                    location: projectionLocation + visibleOffset,
                                    length: visibleRange.length
                                ),
                                source: atomSource,
                                insertionBefore: atomSource.location,
                                insertionAfter: NSMaxRange(atomSource),
                                decodedText: visibleCharacter
                            )
                        )
                    )
                    sourceOffset += atomSource.length
                    visibleOffset += visibleRange.length
                    continue
                }
            }

            // COR-33 stage 2: CRLF in source normalises to LF in rendered code content.
            if sourceOffset + 1 < sourceText.length,
               sourceText.character(at: sourceOffset) == 0x0D,
               sourceText.character(at: sourceOffset + 1) == 0x0A,
               visibleCharacter == "\n" {
                let atomSource = NSRange(location: sourceLocation + sourceOffset, length: 2)
                atoms.append(
                    .atomic(
                        AtomicSourceAtom(
                            kind: .normalizedCodeBlock,
                            projection: NSRange(location: projectionLocation + visibleOffset, length: visibleRange.length),
                            source: atomSource,
                            insertionBefore: atomSource.location,
                            insertionAfter: NSMaxRange(atomSource),
                            decodedText: visibleCharacter
                        )
                    )
                )
                sourceOffset += 2
                visibleOffset += visibleRange.length
                continue
            }

            if sourceOffset < sourceText.length,
               sourceText.character(at: sourceOffset) == 0x26 {
                let remainder = NSRange(
                    location: sourceOffset,
                    length: min(32, sourceText.length - sourceOffset)
                )
                let semicolon = sourceText.range(of: ";", options: [], range: remainder)
                if semicolon.location != NSNotFound {
                    let entityRange = NSRange(
                        location: sourceOffset,
                        length: NSMaxRange(semicolon) - sourceOffset
                    )
                    let spelling = sourceText.substring(with: entityRange)
                    if MarkdownLiteralEncoder.decode(
                        sourceSpelling: spelling,
                        kind: .htmlEntity
                    ) == visibleCharacter {
                        let atomSource = NSRange(
                            location: sourceLocation + sourceOffset,
                            length: entityRange.length
                        )
                        atoms.append(
                            .atomic(
                                AtomicSourceAtom(
                                    kind: .htmlEntity,
                                    projection: NSRange(
                                        location: projectionLocation + visibleOffset,
                                        length: visibleRange.length
                                    ),
                                    source: atomSource,
                                    insertionBefore: atomSource.location,
                                    insertionAfter: NSMaxRange(atomSource),
                                    decodedText: visibleCharacter
                                )
                            )
                        )
                        sourceOffset += entityRange.length
                        visibleOffset += visibleRange.length
                        continue
                    }
                }
            }

            guard sourceOffset < sourceText.length else { return nil }
            let sourceRange = sourceText.rangeOfComposedCharacterSequence(at: sourceOffset)
            guard sourceText.substring(with: sourceRange) == visibleCharacter,
                  sourceRange.length == visibleRange.length else {
                return nil
            }
            let atomSource = NSRange(
                location: sourceLocation + sourceOffset,
                length: sourceRange.length
            )
            atoms.append(
                .identity(
                    IdentityAtom(
                        projection: NSRange(
                            location: projectionLocation + visibleOffset,
                            length: visibleRange.length
                        ),
                        source: atomSource,
                        insertionBefore: atomSource.location,
                        insertionAfter: NSMaxRange(atomSource)
                    )
                )
            )
            sourceOffset += sourceRange.length
            visibleOffset += visibleRange.length
        }

        guard sourceOffset == sourceText.length else { return nil }
        return atoms
    }

    /// Convert atoms back to segments for coordinate-map construction.
    static func toSegments(_ atoms: [ProjectionAtom]) -> [ProjectionSegment] {
        atoms.map { atom in
            switch atom {
            case .identity(let a):
                return .source(
                    projection: a.projection,
                    source: a.source,
                    insertionBefore: a.insertionBefore,
                    insertionAfter: a.insertionAfter
                )
            case .atomic(let a):
                return .source(
                    projection: a.projection,
                    source: a.source,
                    insertionBefore: a.insertionBefore,
                    insertionAfter: a.insertionAfter
                )
            case .synthetic(let a):
                return .synthetic(projection: a.projection, kind: a.kind, insertion: a.insertion)
            case .uneditable(let a):
                return .uneditable(projection: a.projection, reason: a.reason)
            }
        }
    }
}
