//
//  LinkEditorSheetTests.swift
//  Markdown EditorTests
//

import Testing
@testable import Markdown_Editor

struct LinkEditorSheetTests {
    @Test func sheetTypeExistsForWindowAttachedPresentation() {
        let _: LinkEditorSheet.Type = LinkEditorSheet.self
        #expect(true)
    }
}
