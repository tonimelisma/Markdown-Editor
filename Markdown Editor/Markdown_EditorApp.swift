//
//  Markdown_EditorApp.swift
//  Markdown Editor
//
//  Created by Toni Melisma on 7/21/26.
//

import SwiftUI

@main
struct Markdown_EditorApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: Markdown_EditorDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
