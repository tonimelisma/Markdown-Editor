//
//  ContentView.swift
//  Markdown Editor
//
//  Created by Toni Melisma on 7/21/26.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: Markdown_EditorDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

#Preview {
    ContentView(document: .constant(Markdown_EditorDocument()))
}
