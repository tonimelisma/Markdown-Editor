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
        VStack(spacing: 0) {
            MarkdownTextView(text: $document.text)
            Divider()
            HStack {
                Spacer()
                // REQ-044: live word / character count.
                Text("\(TextStats.wordCount(document.text)) words · \(TextStats.characterCount(document.text)) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
        }
    }
}

#Preview {
    ContentView(document: .constant(Markdown_EditorDocument(text: "# Hello\n\nSome **bold** and *italic* text, plus `code`.")))
}
