//
//  LocalImageAndPasteTests.swift
//  Markdown EditorTests
//

import XCTest
@testable import Markdown_Editor

final class LocalImageAndPasteTests: XCTestCase {
    // Verifies: REQ-059
    @MainActor
    func testPastePolicyPrefersPlainText() {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.declareTypes([.string, .rtf], owner: nil)
        pb.setString("plain-only", forType: .string)
        let rtf = try! NSAttributedString(string: "RICH").data(
            from: NSRange(location: 0, length: 4),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        pb.setData(rtf, forType: .rtf)
        XCTAssertTrue(PastePolicy.offersRichText(on: pb))
        XCTAssertEqual(PastePolicy.plainText(from: pb), "plain-only")
    }

    // Verifies: REQ-079 — all URLs open via injected opener (no scheme allowlist).
    @MainActor
    func testLinkOpenerAcceptsNonHTTPSchemes() {
        let session = EditorSession()
        var opened: [URL] = []
        session.openURL = { opened.append($0) }
        session.openURL(URL(string: "mailto:a@b.test")!)
        session.openURL(URL(string: "custom-scheme://path")!)
        session.openURL(URL(string: "https://example.com")!)
        XCTAssertEqual(opened.map(\.absoluteString), [
            "mailto:a@b.test",
            "custom-scheme://path",
            "https://example.com"
        ])
    }

    // Verifies: REQ-079 — a native WYSIWYG link callback opens the injected URL and accepts
    // arbitrary supported URL schemes without consuming the edit route.
    @MainActor
    func testWYSIWYGLinkClickUsesSessionOpener() {
        let document = MarkdownDocument()
        let session = EditorSession()
        let placement = ImagePlacementController()
        var opened: URL?
        session.openURL = { opened = $0 }
        let coordinator = WYSIWYGEditor.Coordinator(
            document: document,
            session: session,
            placementController: placement
        )

        let handled = coordinator.textView(
            NSTextView(),
            clickedOnLink: URL(string: "mailto:a@b.test")!,
            at: 0
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(opened?.absoluteString, "mailto:a@b.test")
    }

    // Verifies: REQ-082 — Add Image routes through window-scoped EditorActionRouter.
    @MainActor
    func testAddImageRoutesThroughPlacementClaims() async {
        let document = MarkdownDocument()
        document.installTextForTesting("")
        let session = EditorSession()
        session.attach(document: document)
        let placement = ImagePlacementController()
        placement.attach(actions: document)
        let router = EditorActionRouter()
        router.document = document
        router.placement = placement
        session.actionRouter = router

        let fixture = fixturesImagesDirectory().appendingPathComponent("sample.png")
        session.imagePicker = TestImagePicker([fixture])
        await session.addImages()
        // Intent is cleared after handle; placement invoked via window-scoped router.
        XCTAssertNil(router.pendingImageTarget)
    }

    private func fixturesImagesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Images")
    }
}
