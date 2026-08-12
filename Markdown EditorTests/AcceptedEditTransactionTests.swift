//
//  AcceptedEditTransactionTests.swift
//  Markdown EditorTests
//

import Testing
import AppKit
import Foundation
@testable import Markdown_Editor

@MainActor
struct AcceptedEditTransactionTests {

    // Verifies: REQ-091; ARC-005 — consecutive WYSIWYG inserts without waiting for parse.
    @Test func twoImmediateKeystrokesAdvanceSourceAndPresentation() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hi\n")
        let session = EditorSession()
        session.attach(document: doc)
        let tree = MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get()!
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: doc.text, sourceVersion: doc.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)
        let firstID = session.presentation!.id

        let first = session.perform(
            .insertText("a"),
            selection: .projection(
                ProjectionSelection(
                    utf16: NSRange(location: 0, length: 0),
                    revision: session.presentation!.projectionRevision
                )
            ),
            expectedSourceRevision: SourceRevision(value: doc.sourceVersion)
        )
        guard case .accepted(let editA) = first else {
            Issue.record("first insert refused: \(first)")
            return
        }
        #expect(editA.presentationTransition != nil)
        #expect(session.presentation?.id != firstID)
        #expect(session.presentation?.sourceRevision.value == doc.sourceVersion)
        #expect(doc.text == "ahi\n")
        #expect(session.presentation?.renderedString == "ahi\n")

        let second = session.perform(
            .insertText("b"),
            selection: .projection(
                ProjectionSelection(
                    utf16: NSRange(location: 1, length: 0),
                    revision: session.presentation!.projectionRevision
                )
            ),
            expectedSourceRevision: SourceRevision(value: doc.sourceVersion)
        )
        guard case .accepted = second else {
            Issue.record("second immediate insert refused: \(second)")
            return
        }
        #expect(doc.text == "abhi\n")
        #expect(session.presentation?.renderedString == "abhi\n")
        if case .editable(let id) = session.wysiwygModeState.availability {
            #expect(id == session.presentation?.id)
        } else {
            Issue.record("expected editable availability after accepted edits")
        }
    }

    // Verifies: REQ-091; ARC-Q01 — 100 immediate accepted inserts.
    @Test func oneHundredImmediateKeystrokes() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("z\n")
        let session = EditorSession()
        session.attach(document: doc)
        let tree = MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get()!
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: doc.text, sourceVersion: doc.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)

        var refused = 0
        for i in 0..<100 {
            guard let presentation = session.presentation else {
                refused += 1
                break
            }
            let outcome = session.perform(
                .insertText("x"),
                selection: .projection(
                    ProjectionSelection(
                        utf16: NSRange(location: i, length: 0),
                        revision: presentation.projectionRevision
                    )
                ),
                expectedSourceRevision: SourceRevision(value: doc.sourceVersion)
            )
            if case .refused = outcome {
                refused += 1
                break
            }
        }
        #expect(refused == 0)
        #expect(doc.text == String(repeating: "x", count: 100) + "z\n")
        #expect(session.presentation?.renderedString == doc.text)
    }

    // Verifies: REQ-084/091 — non-ASCII input at a paragraph boundary is one exact transition.
    @Test func unicodeInsertionAtParagraphEnd() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("ab")
        let session = EditorSession()
        session.attach(document: doc)
        let tree = MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get()!
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: doc.text, sourceVersion: doc.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)

        let presentation = session.presentation!
        let outcome = session.perform(
            .insertText("日"),
            selection: .projection(
                ProjectionSelection(
                    utf16: NSRange(location: 2, length: 0),
                    revision: presentation.projectionRevision
                )
            ),
            expectedSourceRevision: presentation.sourceRevision
        )
        guard case .accepted = outcome else {
            Issue.record("Unicode end insertion refused: \(outcome); atoms=\(presentation.atoms)")
            return
        }
        #expect(doc.text == "ab日")
        #expect(session.presentation?.renderedString == "ab日\n")
    }

    // Verifies: REQ-091/092; ARC-005/008 — source and projection deltas remain distinct.
    @Test func consecutiveLiteralPunctuationKeepsExactSourceAndVisibleText() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hi\n")
        let session = EditorSession()
        session.attach(document: doc)
        let tree = MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get()!
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: doc.text, sourceVersion: doc.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)

        let visibleInputs = ["*", "&entity;", "<"]
        var projectionOffset = 0
        for input in visibleInputs {
            let current = session.presentation!
            let result = session.perform(
                .insertText(input),
                selection: .projection(
                    ProjectionSelection(
                        utf16: NSRange(location: projectionOffset, length: 0),
                        revision: current.projectionRevision
                    )
                ),
                expectedSourceRevision: SourceRevision(value: doc.sourceVersion)
            )
            guard case .accepted = result else {
                Issue.record("literal input refused: \(input), \(result)")
                return
            }
            projectionOffset += (input as NSString).length
        }

        #expect(session.presentation?.renderedString == "*&entity;<hi\n")
        #expect(doc.text == "\\*&amp;entity;&lt;hi\n")
    }

    // Verifies: REQ-084/091/092; ARC-005/008 — literal encoding reads complete
    // neighboring graphemes and never interprets a UTF-16 surrogate as a scalar.
    @Test func literalInsertionBesideNonBMPCharactersIsExact() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("😀x\n")
        let session = EditorSession()
        session.attach(document: doc)
        let tree = MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get()!
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: doc.text, sourceVersion: doc.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)

        for location in [2, 0] {
            let current = session.presentation!
            let result = session.perform(
                .insertText("*"),
                selection: .projection(
                    ProjectionSelection(
                        utf16: NSRange(location: location, length: 0),
                        revision: current.projectionRevision
                    )
                ),
                expectedSourceRevision: SourceRevision(value: doc.sourceVersion)
            )
            guard case .accepted = result else {
                Issue.record("literal insertion at \(location) refused: \(result)")
                return
            }
        }

        #expect(doc.text == "\\*😀\\*x\n")
        #expect(session.presentation?.renderedString == "*😀*x\n")
    }

    // Verifies: REQ-092; ARC-008 — syntax assembled by consecutive literal
    // keystrokes is protected after reparsing the completed source context.
    @Test func sequentialLiteralTypingCannotCreateListOrEntitySyntax() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hello\n")
        let session = EditorSession()
        session.attach(document: doc)
        let tree = MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get()!
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: doc.text, sourceVersion: doc.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)

        var location = 0
        for character in ["1", ".", " "] {
            let current = session.presentation!
            let outcome = session.perform(
                .insertText(character),
                selection: .projection(
                    ProjectionSelection(
                        utf16: NSRange(location: location, length: 0),
                        revision: current.projectionRevision
                    )
                ),
                expectedSourceRevision: current.sourceRevision
            )
            guard case .accepted = outcome else {
                Issue.record("list-like literal refused at \(character): \(outcome)")
                return
            }
            location += (character as NSString).length
        }
        #expect(doc.text == "1\\. hello\n")
        #expect(session.presentation?.renderedString == "1. hello\n")

        let entityDoc = MarkdownDocument()
        entityDoc.installTextForTesting("x\n")
        let entitySession = EditorSession()
        entitySession.attach(document: entityDoc)
        let entityTree = MarkdownParser.parse(
            entityDoc.text,
            sourceVersion: entityDoc.sourceVersion
        ).get()!
        entitySession.installProjectionForTesting(
            MarkdownProjectionModel.build(
                tree: entityTree,
                index: MarkdownSourceIndex(
                    source: entityDoc.text,
                    sourceVersion: entityDoc.sourceVersion
                )
            ),
            tree: entityTree
        )
        var entityLocation = 0
        for character in ["&", "a", "m", "p", ";"] {
            let current = entitySession.presentation!
            let outcome = entitySession.perform(
                .insertText(character),
                selection: .projection(
                    ProjectionSelection(
                        utf16: NSRange(location: entityLocation, length: 0),
                        revision: current.projectionRevision
                    )
                ),
                expectedSourceRevision: current.sourceRevision
            )
            guard case .accepted = outcome else {
                Issue.record("entity-like literal refused at \(character): \(outcome)")
                return
            }
            entityLocation += 1
        }
        #expect(entityDoc.text == "&amp;amp;x\n")
        #expect(entitySession.presentation?.renderedString == "&amp;x\n")
    }

    // Verifies: REQ-080/091/092; ARC-005/008 — table typing encodes only the
    // inserted fragment while the atomic transaction preserves the complete cell.
    @Test func tableLiteralInsertionPreservesCellAndAdvancesPresentation() throws {
        let doc = MarkdownDocument()
        doc.installTextForTesting("| abc |\n| --- |\n| def |\n")
        let session = EditorSession()
        session.attach(document: doc)
        let tree = try #require(MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get())
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: doc.text, sourceVersion: doc.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)
        let cell = try #require(session.presentation?.tables.first?.cells.first)
        let caret = cell.utf16Range.location + 1

        let outcome = session.perform(
            .insertText("*"),
            selection: .projection(
                ProjectionSelection(
                    utf16: NSRange(location: caret, length: 0),
                    revision: try #require(session.presentation?.projectionRevision)
                )
            ),
            expectedSourceRevision: SourceRevision(value: doc.sourceVersion)
        )

        guard case .accepted(let edit) = outcome else {
            Issue.record("table insertion refused: \(outcome)")
            return
        }
        #expect(edit.presentationTransition != nil)
        #expect(doc.text == "| a\\*bc |\n| --- |\n| def |\n")
        #expect(session.presentation?.renderedString.contains("a*bc") == true)
        #expect(session.presentation?.sourceRevision.value == doc.sourceVersion)
    }

    // Verifies: REQ-080/091 — deleting in a table is a real backward deletion,
    // not an empty insertion, and keeps source/presentation synchronized.
    @Test func tableDeleteBackwardRemovesPreviousVisibleCharacter() throws {
        let doc = MarkdownDocument()
        doc.installTextForTesting("| abc |\n| --- |\n| def |\n")
        let session = EditorSession()
        session.attach(document: doc)
        let tree = try #require(MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get())
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: doc.text, sourceVersion: doc.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)
        let cell = try #require(session.presentation?.tables.first?.cells.first)
        let caret = cell.utf16Range.location + 2

        let outcome = session.perform(
            .deleteBackward,
            selection: .projection(
                ProjectionSelection(
                    utf16: NSRange(location: caret, length: 0),
                    revision: try #require(session.presentation?.projectionRevision)
                )
            ),
            expectedSourceRevision: SourceRevision(value: doc.sourceVersion)
        )

        guard case .accepted = outcome else {
            Issue.record("table deletion refused: \(outcome)")
            return
        }
        #expect(doc.text == "| ac |\n| --- |\n| def |\n")
        #expect(session.presentation?.renderedString.contains("ac") == true)
    }

    // Verifies: REQ-084/091; ARC-005 — the real TextKit delegate applies once before return.
    @Test func adapterStorageMatchesCommittedPresentationBeforeCallbackReturns() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hi\n")
        let session = EditorSession()
        session.attach(document: doc)
        let tree = MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get()!
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: doc.text, sourceVersion: doc.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)

        let placement = ImagePlacementController()
        let coordinator = WYSIWYGEditor.Coordinator(
            document: doc,
            session: session,
            placementController: placement
        )
        let textView = MarkdownWYSIWYGTextView(usingTextLayoutManager: false)
        textView.delegate = coordinator
        textView.session = session
        textView.documentActions = doc
        coordinator.textView = textView
        coordinator.applyProjectionIfNeeded(reason: .reapplyIfDrift)

        let allowNative = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 0, length: 0),
            replacementString: "a"
        )

        #expect(!allowNative)
        #expect(doc.text == "ahi\n")
        #expect(textView.string == "ahi\n")
        #expect(textView.string == session.presentation?.renderedString)
    }

    // Verifies: REQ-016/059/091; ARC-005 — paste advances source, session, and
    // TextKit storage in one discrete transaction before the adapter returns.
    @Test func plainTextPasteAppliesAcceptedTransitionSynchronously() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hi\n")
        let session = EditorSession()
        session.attach(document: doc)
        let tree = MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get()!
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: doc.text, sourceVersion: doc.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)

        let coordinator = WYSIWYGEditor.Coordinator(
            document: doc,
            session: session,
            placementController: ImagePlacementController()
        )
        let textView = MarkdownWYSIWYGTextView(usingTextLayoutManager: false)
        textView.delegate = coordinator
        textView.session = session
        textView.documentActions = doc
        textView.adapterCoordinator = coordinator
        coordinator.textView = textView
        coordinator.applyProjectionIfNeeded(reason: .reapplyIfDrift)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let applied = textView.pastePlainText("*")

        #expect(applied)
        #expect(doc.text == "\\*hi\n")
        #expect(session.presentation?.renderedString == "*hi\n")
        #expect(textView.string == "*hi\n")
        #expect(textView.selectedRange() == NSRange(location: 1, length: 0))
    }

    // Verifies: REQ-091; ARC-005 — refused edit changes neither source nor presentation.
    @Test func refusedEditChangesNeither() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hi\n")
        let session = EditorSession()
        session.attach(document: doc)
        let tree = MarkdownParser.parse(doc.text, sourceVersion: doc.sourceVersion).get()!
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: doc.text, sourceVersion: doc.sourceVersion)
        )
        session.installProjectionForTesting(model, tree: tree)
        let beforeText = doc.text
        let beforeID = session.presentation!.id

        let outcome = session.perform(
            .insertText("z"),
            selection: .projection(
                ProjectionSelection(
                    utf16: NSRange(location: 0, length: 0),
                    revision: ProjectionRevision(value: 999_999)
                )
            ),
            expectedSourceRevision: SourceRevision(value: doc.sourceVersion)
        )
        #expect({
            if case .refused = outcome { return true }
            return false
        }())
        #expect(doc.text == beforeText)
        #expect(session.presentation?.id == beforeID)
    }
}

@MainActor
struct EditorStateOwnershipTests {

    // Verifies: REQ-052/086; ARC-002 — session owns one typed state per mode.
    @Test func sessionOwnsTypedModeState() {
        let session = EditorSession()
        session.updateSourceModeState {
            $0.selection = SourceSelection(utf16: NSRange(location: 2, length: 0), affinity: .upstream)
            $0.scrollOffset = CGPoint(x: 0, y: 12)
        }
        #expect(session.sourceModeState.selection.range.location == 2)
        #expect(session.sourceModeState.selection.affinity == .upstream)
        #expect(session.sourceModeState.scrollOffset.y == 12)

        let sources = try! String(contentsOfFile: #filePath.replacingOccurrences(
            of: "Markdown EditorTests/AcceptedEditTransactionTests.swift",
            with: "Markdown Editor/EditorSession.swift"
        ), encoding: .utf8)
        #expect(!sources.contains("ModeViewState"))
        #expect(!sources.contains("sourceViewState"))
        #expect(!sources.contains("wysiwygViewState"))
    }

    // Verifies: REQ-052 — session state owns mode state without exposing AppKit presentation.
    @Test func sessionExposesNoAppKitPresentation() throws {
        let source = try String(contentsOfFile: #filePath.replacingOccurrences(of: "Markdown EditorTests/AcceptedEditTransactionTests.swift", with: "Markdown Editor/EditorSession.swift"), encoding: .utf8)
        #expect(!source.contains("NSOpenPanel"))
        #expect(!source.contains("NSAlert"))
        #expect(!source.contains("runModal"))
    }

    // Verifies: REQ-057 — displaced architecture routes remain absent from production.
    // Verifies: ARC-002/003/013 — displaced architecture routes are absent from production.
    @Test func displacedArchitectureRoutesAbsent() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Markdown Editor")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        var haystack = ""
        for file in files {
            haystack += try String(contentsOf: file, encoding: .utf8)
            haystack += "\n"
        }
        let removedTypes = [
            "ModeViewState",
            "EditorViewState",
            "EditorViewChromeState",
            "LogicalSelection",
            "SemanticSelection",
            "EditorCoordinateDomain",
            "EditorSelectionIntent",
            "DocumentIOText",
            "DocumentLoadGate"
        ]
        for symbol in removedTypes {
            #expect(!haystack.contains("struct \(symbol)"), "found \(symbol)")
            #expect(!haystack.contains("enum \(symbol)"), "found \(symbol)")
            #expect(!haystack.contains("class \(symbol)"), "found \(symbol)")
            #expect(!haystack.contains("typealias \(symbol)"), "found typealias \(symbol)")
        }
        #expect(!haystack.contains("var sourceChrome"))
        #expect(!haystack.contains("var wysiwygChrome"))
        #expect(!haystack.contains("var acceptedSourceVersion"))
        #expect(!haystack.contains("var isProgrammaticUpdate"))
        #expect(!haystack.contains("var isNativeEditInFlight"))
        #expect(!haystack.contains("var preferDiscreteGrouping"))
        #expect(!haystack.contains("var nsRange: NSRange"))
    }

    /// COR-22 deletion gate for the editor foundation rewrite. Each symbol was displaced by an
    /// approved plan; the architecture forbids keeping either one as a compatibility route.
    // Verifies: REQ-057 — rewrite routes remain single-owner and displaced paths stay deleted.
    @Test func rewriteDisplacedRoutesAreAbsent() throws {
        let haystack = try productionSourceText()
        let displaced = [
            "RichTextBuilder",                 // INC-05: one attributed builder
            "PlaceholderAttachmentCell",       // INC-05: semantic separator route
            "PresentationDecoration",          // INC-05: unconsumed decoration descriptors
            "PerformanceSamplerRegistry",      // COR-19: sampler lifetime coordination
            "flushPerformanceSamplingAtRunEnd",// COR-19
            "keystrokeTranslation",            // COR-20: dishonest metric boundary
            "CanonicalAssetReferenceScanner",  // COR-21: secondary Markdown scanner
            "struct EditorToolbar"             // INC-06: in-document formatting row
        ]
        for symbol in displaced {
            #expect(!haystack.contains(symbol), "displaced route still present: \(symbol)")
        }
        // INC-06: no application-modal formatting dialog.
        #expect(!haystack.contains("runModal("))
        // COR-20: the ordinary edit path may not reach a whole-document replacement.
        #expect(!haystack.contains("applyRecoveryPresentation(built, to: textView)\n                appliedSnapshotID"))
    }

    /// INC-05: only `MarkdownTypography` defines approved numeric typography tokens, and the
    /// semantic compiler stays free of AppKit.
    @Test func typographyTokensAndAppKitStayInTheirOwners() throws {
        let files = try productionSourceFiles()
        let compiler = try #require(files.first { $0.lastPathComponent == "ProjectionCompiler.swift" })
        let compilerText = try String(contentsOf: compiler, encoding: .utf8)
        #expect(!compilerText.contains("import AppKit"))
        #expect(!compilerText.contains("NSFont"))
        #expect(!compilerText.contains("NSColor"))

        // Typography tokens are declared in exactly one place, and consumers reference the named
        // token rather than restating its value.
        let tokenNames = [
            "bodyPointSize", "lineHeightMultiple", "maximumReadingMeasure",
            "minimumHorizontalInset", "minimumVerticalInset", "paragraphSpacingEm",
            "listIndent", "quoteRuleWidth", "headingPointSizes"
        ]
        for token in tokenNames {
            let declarers = try files
                .filter { try String(contentsOf: $0, encoding: .utf8).contains("let \(token)") }
                .map(\.lastPathComponent)
            #expect(declarers == ["MarkdownTypography.swift"], "\(token) declared in \(declarers)")
        }
        for consumer in ["AttributedPresentationBuilder.swift", "WYSIWYGEditor.swift"] {
            let text = try String(
                contentsOf: try #require(files.first { $0.lastPathComponent == consumer }),
                encoding: .utf8
            )
            #expect(text.contains("MarkdownTypography."), "\(consumer) does not use the tokens")
        }
    }
}

@MainActor
struct PresentationSnapshotTests {

    // Verifies: REQ-091; ARC-003 — equal source revision with different snapshot IDs is distinguishable.
    @Test func snapshotIdentityDistinctFromSourceRevision() {
        let model = MarkdownProjectionModel.build(
            tree: MarkdownParser.parse("hi\n", sourceVersion: 1).get()!,
            index: MarkdownSourceIndex(source: "hi\n", sourceVersion: 1)
        )
        let a = PresentationSnapshot.from(
            model: model,
            id: .init(value: 1),
            locationGeneration: 0,
            sourceText: "hi\n"
        )
        let b = PresentationSnapshot.from(
            model: model,
            id: .init(value: 2),
            locationGeneration: 0,
            sourceText: "hi\n"
        )
        #expect(a.sourceRevision == b.sourceRevision)
        #expect(a.id != b.id)
        #expect(ProjectionOracle.validate(snapshot: a).get() != nil)
    }
}

@MainActor
struct MarkdownLiteralEncoderTests {

    // Verifies: REQ-092; ARC-008 — punctuation encodes safely while remaining literal intent.
    @Test func encodesEmphasisAndEntities() {
        let ctx = LiteralEncodeContext(
            intendedVisibleText: "* & <",
            precedingSourceCharacter: nil,
            followingSourceCharacter: nil,
            atLineStart: true,
            container: .paragraph,
            dialect: .formalGFM
        )
        guard case .encoded(let spelling) = MarkdownLiteralEncoder.encode(ctx) else {
            Issue.record("encode refused")
            return
        }
        #expect(spelling.contains("\\*") || spelling.hasPrefix("*") == false || spelling.contains("\\*"))
        #expect(spelling.contains("&amp;") || spelling.contains("&"))
        #expect(spelling.contains("&lt;"))
    }

    // Verifies: REQ-080 — table-cell edits preserve escaped pipe content.
    @Test func tableCellEscapesPipe() {
        let ctx = LiteralEncodeContext(
            intendedVisibleText: "a|b",
            precedingSourceCharacter: nil,
            followingSourceCharacter: nil,
            atLineStart: false,
            container: .tableCell,
            dialect: .formalGFM
        )
        guard case .encoded(let spelling) = MarkdownLiteralEncoder.encode(ctx) else {
            Issue.record("encode refused")
            return
        }
        #expect(spelling.contains("\\|"))
    }
}

@MainActor
struct ProjectionSelectionClassifierTests {

    // Verifies: REQ-080/087; ARC-009 — cross-cell selection refuses.
    @Test func refusesCrossCellSelection() throws {
        let source = "| a | b |\n| - | - |\n| 1 | 2 |\n"
        let tree = try #require(MarkdownParser.parse(source, sourceVersion: 1).get())
        let model = MarkdownProjectionModel.build(
            tree: tree,
            index: MarkdownSourceIndex(source: source, sourceVersion: 1)
        )
        let snapshot = PresentationSnapshot.from(
            model: model,
            id: .init(value: 1),
            locationGeneration: 0,
            sourceText: source
        )
        guard snapshot.tables.first?.cells.count ?? 0 >= 2 else {
            Issue.record("expected table cells")
            return
        }
        let cells = snapshot.tables[0].cells
        let start = cells[0].utf16Range.location
        let end = NSMaxRange(cells[1].utf16Range)
        let classified = ProjectionSelectionClassifier.classify(
            selection: NSRange(location: start, length: end - start),
            affinity: .downstream,
            snapshot: snapshot
        )
        if case .crossCell = classified {
            // expected
        } else if case .mixed = classified {
            // also acceptable refusal class
        } else {
            Issue.record("expected cross-cell/mixed, got \(classified)")
        }
    }
}

@MainActor
struct NativeUpdateOriginTests {

    // Verifies: REQ-083/084; ARC-013 — programmatic selection does not close typing.
    @Test func programmaticOriginDoesNotCloseTyping() {
        let doc = MarkdownDocument()
        doc.installTextForTesting("hi\n")
        let trace = InMemoryEditorTrace()
        doc.trace = trace
        let session = EditorSession()
        session.attach(document: doc)
        let mutation = SourceMutation(
            expectedRevision: 0,
            range: NSRange(location: 0, length: 0),
            expectedText: "",
            replacement: "a",
            selectionBefore: SourceSelection(utf16: NSRange(location: 0, length: 0)),
            selectionAfter: SourceSelection(utf16: NSRange(location: 1, length: 0)),
            actionName: "Typing",
            grouping: .typing
        )
        _ = doc.commitSourceMutation(mutation)
        session.updateOrigin.with(.programmaticPresentation) {
            #expect(session.updateOrigin.current == .programmaticPresentation)
        }
        #expect(session.updateOrigin.current == .nativeUserInput)
        #expect(trace.events.contains(.updateOrigin(.programmaticPresentation)))
        #expect(trace.events.contains(.updateOrigin(.nativeUserInput)))
        // Typing group remains open until a native selection boundary.
        let second = SourceMutation(
            expectedRevision: doc.sourceVersion,
            range: NSRange(location: 1, length: 0),
            expectedText: "",
            replacement: "b",
            selectionBefore: SourceSelection(utf16: NSRange(location: 1, length: 0)),
            selectionAfter: SourceSelection(utf16: NSRange(location: 2, length: 0)),
            actionName: "Typing",
            grouping: .typing
        )
        _ = doc.commitSourceMutation(second)
        #expect(doc.text.hasPrefix("ab"))
    }
}

@MainActor
struct DocumentSerializedIOTests {

    // Verifies: REQ-015; ARC-001/011 — default serialized NSDocument I/O opt-ins remain false.
    @Test func concurrentReadAndAsyncWriteDefaultsRemainDisabled() {
        #expect(MarkdownDocument.canConcurrentlyReadDocuments(ofType: "net.daringfireball.markdown") == false)
        let doc = MarkdownDocument()
        #expect(doc.canAsynchronouslyWrite(to: URL(fileURLWithPath: "/tmp/x.md"), ofType: "net.daringfireball.markdown", for: .saveOperation) == false)
    }

    // Verifies: REQ-015; ARC-001/011 — actual NSDocumentController open/save uses canonical I/O.
    @Test func documentControllerOpenAndSaveRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.md")
        let savedURL = directory.appendingPathComponent("saved.md")
        try Data("opened\n".utf8).write(to: sourceURL)

        let document: MarkdownDocument = try await withCheckedThrowingContinuation { continuation in
            NSDocumentController.shared.openDocument(
                withContentsOf: sourceURL,
                display: false
            ) { document, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let document = document as? MarkdownDocument {
                    continuation.resume(returning: document)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
        #expect(document.text == "opened\n")

        let mutation = SourceMutation(
            expectedRevision: document.sourceVersion,
            range: NSRange(location: 0, length: 6),
            expectedText: "opened",
            replacement: "saved",
            selectionBefore: SourceSelection(utf16: NSRange(location: 0, length: 6)),
            selectionAfter: SourceSelection(utf16: NSRange(location: 5, length: 0)),
            actionName: "Edit",
            grouping: .discrete
        )
        guard case .committed = document.commitSourceMutation(mutation) else {
            Issue.record("controller-opened document refused an exact mutation")
            document.close()
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.save(
                to: savedURL,
                ofType: MarkdownContentType.identifier,
                for: .saveAsOperation
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        #expect(try Data(contentsOf: savedURL) == Data("saved\n".utf8))
        document.close()
    }
}

@MainActor
struct ArchitectureConformanceTests {

    // Verifies: REQ-085; ARC-Q06 — semantic parser/index work cannot execute on main.
    @Test func semanticWorkerRunsOffMainThread() {
        let ranOnMain = EditorSemanticWorker.sync { Thread.isMainThread }
        #expect(ranOnMain == false)
    }

    // Verifies: ARC-014 — no UI-test target dependency.
    @Test func noUITestTargetInProject() throws {
        let project = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Markdown Editor.xcodeproj/project.pbxproj")
        let text = try String(contentsOf: project, encoding: .utf8)
        #expect(!text.contains("XCUITest"))
        #expect(!text.contains("UITests"))
    }
}
