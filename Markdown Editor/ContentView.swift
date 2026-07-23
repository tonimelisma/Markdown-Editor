//
//  ContentView.swift
//  Markdown Editor
//
//  Created by Toni Melisma on 7/21/26.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: Markdown_EditorDocument
    @State private var counts = TextStats.Counts(words: 0, characters: 0)
    @State private var statsComputer = TextStatsComputer()

    var body: some View {
        VStack(spacing: 0) {
            MarkdownTextView(text: $document.text)
            Divider()
            HStack {
                Spacer()
                // REQ-044: live word / character count.
                Text("\(counts.words) words · \(counts.characters) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
        }
        // REQ-044/045: count a snapshot off-main so a large document does not add CPU work
        // to the synchronous text-editing path. The actor observes task cancellation while
        // scanning, so a newer edit coalesces stale count work promptly.
        .task(id: document.text) {
            let snapshot = document.text
            guard let next = await statsComputer.counts(for: snapshot), !Task.isCancelled else { return }
            counts = next
        }
    }
}

#Preview {
    ContentView(document: .constant(Markdown_EditorDocument(text: "# Hello\n\nSome **bold** and *italic* text, plus `code`.")))
}
