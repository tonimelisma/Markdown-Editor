//
//  TextStorageApplierTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

/// Records every mutation TextKit receives, so "one bounded edit, no full replacement" is proven
/// against the storage API rather than inferred from the resulting string.
///
/// Deliberately not `@MainActor`: `NSTextStorage`'s primitives are nonisolated overrides, and the
/// object is only ever used from the main actor by these tests.
final class SpyTextStorage: NSTextStorage {
    private let backing = NSMutableAttributedString()
    private(set) var characterReplacements: [NSRange] = []
    private(set) var attributeReplacements: [NSRange] = []
    private(set) var fullReplacements = 0
    /// Optional stall injected inside the mutation, used to prove a timing boundary encloses it.
    var mutationDelay: TimeInterval = 0

    override init() { super.init() }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @available(*, unavailable)
    required init(itemProviderData data: Data, typeIdentifier: String) throws {
        fatalError("init(itemProviderData:typeIdentifier:) has not been implemented")
    }

    @available(*, unavailable)
    required init(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
        fatalError("init(pasteboardPropertyList:ofType:) has not been implemented")
    }

    func resetSpy() {
        characterReplacements.removeAll()
        attributeReplacements.removeAll()
        fullReplacements = 0
    }

    override var string: String { backing.string }

    override func attributes(
        at location: Int,
        effectiveRange range: NSRangePointer?
    ) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    /// Counted at the API that means "rebuild everything", not inferred from a range that merely
    /// happens to span a single-block document.
    override func setAttributedString(_ attrString: NSAttributedString) {
        fullReplacements += 1
        super.setAttributedString(attrString)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        characterReplacements.append(range)
        if mutationDelay > 0 { Thread.sleep(forTimeInterval: mutationDelay) }
        backing.replaceCharacters(in: range, with: str)
        edited(
            .editedCharacters,
            range: range,
            changeInLength: (str as NSString).length - range.length
        )
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        attributeReplacements.append(range)
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
    }
}

@MainActor
func makeSpyBackedTextView(width: CGFloat = 400) -> (MarkdownWYSIWYGTextView, SpyTextStorage) {
    let storage = SpyTextStorage()
    let layoutManager = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
    storage.addLayoutManager(layoutManager)
    layoutManager.addTextContainer(container)
    let textView = MarkdownWYSIWYGTextView(
        frame: NSRect(x: 0, y: 0, width: width, height: 200),
        textContainer: container
    )
    return (textView, storage)
}

/// A current snapshot, an accepted identity insertion, and the resulting transition.
@MainActor
struct PatchFixture {
    let current: PresentationSnapshot
    let next: PresentationSnapshot
    let transition: PresentationTransition
    let builtCurrent: AttributedPresentation

    init(source: String, insert: String, at location: Int) throws {
        let index = MarkdownSourceIndex(source: source, sourceVersion: 1)
        let tree = try #require(MarkdownParser.parse(source, sourceVersion: 1).get())
        let model = MarkdownProjectionModel.build(tree: tree, index: index)
        current = PresentationSnapshot.from(
            model: model,
            id: PresentationSnapshot.ID(value: 1),
            locationGeneration: 1,
            sourceText: source
        )
        let sourceLength = (source as NSString).length
        transition = try #require(
            PresentationTransitionPlanner.identityReplacement(
                snapshot: current,
                projectionRange: NSRange(location: location, length: 0),
                visibleReplacement: insert,
                sourceRange: NSRange(location: location, length: 0),
                sourceReplacement: insert,
                nextSourceRevision: SourceRevision(value: 2),
                nextSourceUTF16Count: sourceLength + (insert as NSString).length,
                nextSnapshotID: PresentationSnapshot.ID(value: 2),
                affinity: .downstream
            )
        )
        next = transition.nextSnapshot
        builtCurrent = AttributedPresentationBuilder.build(
            model: current.asProjectionModel,
            theme: MarkdownTypography()
        )
    }

    func makePatch() -> PresentationPatch? {
        PresentationPatch.make(
            transition: transition,
            current: current,
            buildScope: { model, scope in
                AttributedPresentationBuilder.buildScoped(
                    model: model,
                    theme: MarkdownTypography(),
                    scope: scope
                )
            }
        )
    }
}

@MainActor
struct TextStorageApplierTests {
    // Verifies: REQ-109; ARC-Q16 — one bounded range edit, zero full replacements.
    @Test func ordinaryInsertionUsesOneBoundedRangePatch() throws {
        let fixture = try PatchFixture(
            source: "First paragraph.\n\nSecond paragraph stays untouched.\n",
            insert: "!",
            at: 16
        )
        let patch = try #require(fixture.makePatch())

        let (textView, storage) = makeSpyBackedTextView()
        let applier = TextStorageApplier()
        applier.applyInitialPresentation(fixture.builtCurrent, to: textView)
        storage.resetSpy()

        #expect(applier.applyPatch(patch, to: textView, expectedCurrent: fixture.current))

        #expect(storage.fullReplacements == 0)
        #expect(storage.characterReplacements == [patch.currentRange])
        // Bounded: the patch touches the edited paragraph, not the whole document.
        #expect(patch.currentRange.length < (fixture.current.renderedString as NSString).length)
        #expect(textView.string == fixture.next.renderedString)
        #expect(textView.selectedRange() == patch.selectionAfter?.range.utf16)
    }

    // Verifies: REQ-109 — the patch scope covers whole semantic blocks and no more.
    @Test func patchScopeCoversTheTouchedBlockAndNoMore() throws {
        let fixture = try PatchFixture(
            source: "First paragraph.\n\nSecond paragraph stays untouched.\n",
            insert: "!",
            at: 16
        )
        let patch = try #require(fixture.makePatch())
        let paragraphs = fixture.current.blocks.filter {
            if case .paragraph = $0.kind { return true }
            return false
        }
        #expect(paragraphs.count == 2)
        let trailing = try #require(paragraphs.last)
        // The untouched trailing paragraph is outside the patch entirely.
        #expect(NSIntersectionRange(patch.currentRange, trailing.projectionRange).length == 0)
        #expect(patch.replacement.length == patch.nextRange.length)
    }

    // Verifies: REQ-109 — a patch against storage that is not its own snapshot changes nothing.
    @Test func patchRefusesWhenAppliedStorageIsStale() throws {
        let fixture = try PatchFixture(source: "hello\n", insert: "!", at: 5)
        let patch = try #require(fixture.makePatch())

        let (textView, storage) = makeSpyBackedTextView()
        textView.textStorage?.setAttributedString(NSAttributedString(string: "stale\n"))
        storage.resetSpy()

        #expect(!TextStorageApplier().applyPatch(patch, to: textView, expectedCurrent: fixture.current))
        #expect(storage.characterReplacements.isEmpty)
        #expect(textView.string == "stale\n")
    }

    // Verifies: REQ-109 — attachment identity survives a patch without a document-wide rebuild.
    @Test func attachmentLookupIsSplicedRatherThanRebuilt() throws {
        let source = "- [ ] task one\n\nTrailing paragraph.\n"
        let fixture = try PatchFixture(
            source: source,
            insert: "!",
            // Projection coordinates: the checkbox and marker replace the "- [ ] " source run,
            // so the end of the trailing paragraph is not at the source offset.
            at: ("\u{FFFC} task one\nTrailing paragraph." as NSString).length
        )
        let patch = try #require(fixture.makePatch())

        let (textView, _) = makeSpyBackedTextView()
        let applier = TextStorageApplier()
        applier.applyInitialPresentation(fixture.builtCurrent, to: textView)
        let checkboxBefore = try #require(applier.attachmentNodes.keys.sorted().first)

        #expect(applier.applyPatch(patch, to: textView, expectedCurrent: fixture.current))

        // The checkbox precedes the edit, so it keeps its location and node identity even though
        // the patch never rebuilt that part of the document.
        #expect(applier.attachmentNodes[checkboxBefore] != nil)
        let expected = AttributedPresentationBuilder.build(
            model: fixture.next.asProjectionModel,
            theme: MarkdownTypography()
        )
        #expect(applier.attachmentNodes == expected.attachmentNodes)
    }
}
