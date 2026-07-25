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
        // REQ-060/075: pass live fileURL so untitled vs saved placement can decide.
        DocumentGroup(newDocument: Markdown_EditorDocument()) { file in
            ContentView(document: file.$document, documentURL: file.fileURL)
        }
    }
}
