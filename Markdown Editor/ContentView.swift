//
//  ContentView.swift
//  Markdown Editor
//
//  Created by Toni Melisma on 7/21/26.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: Markdown_EditorDocument
    var documentURL: URL?
    @State private var counts = TextStats.Counts(words: 0, characters: 0)
    @State private var statsComputer = TextStatsComputer()
    @StateObject private var placementCoordinator = ImagePlacementCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            MarkdownTextView(
                text: $document.text,
                documentURL: documentURL,
                placementCoordinator: placementCoordinator
            )
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
        .task(id: document.text) {
            let snapshot = document.text
            guard let next = await statsComputer.counts(for: snapshot), !Task.isCancelled else { return }
            counts = next
        }
        .onChange(of: documentURL) { _, newURL in
            placementCoordinator.updateDocumentURL(newURL)
        }
        .alert(alertTitle, isPresented: alertPresented) {
            Button("OK", role: .cancel) { placementCoordinator.alert = nil }
        } message: {
            Text(alertMessage)
        }
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { placementCoordinator.alert != nil },
            set: { if !$0 { placementCoordinator.alert = nil } }
        )
    }

    private var alertTitle: String {
        switch placementCoordinator.alert {
        case .error: return "Couldn’t Add Image"
        case .warning: return "Assets Warning"
        case .info: return "Image Action"
        case nil: return ""
        }
    }

    private var alertMessage: String {
        switch placementCoordinator.alert {
        case .error(let m), .warning(let m), .info(let m): return m
        case nil: return ""
        }
    }
}

#Preview {
    ContentView(
        document: .constant(Markdown_EditorDocument(text: "# Hello\n\nSome **bold** and *italic* text, plus `code`.")),
        documentURL: nil
    )
}
