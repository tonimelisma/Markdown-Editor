//
//  ContentView.swift
//  Markdown Editor
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    @State private var counts = TextStats.Counts(words: 0, characters: 0)
    @State private var statsComputer = TextStatsComputer()
    @StateObject private var placementController = ImagePlacementController()
    @StateObject private var session = EditorSession()

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(document: document, session: session)
            Divider()
            Group {
                if session.mode == .wysiwyg {
                    WYSIWYGTextView(
                        document: document,
                        session: session,
                        placementController: placementController
                    )
                } else {
                    MarkdownTextView(
                        document: document,
                        placementController: placementController,
                        session: session
                    )
                }
            }
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
        .onAppear {
            placementController.attach(actions: document)
            placementController.updateDocumentURL(document.publishedFileURL ?? document.fileURL)
            session.attach(document: document)
        }
        .onChange(of: document.publishedFileURL) { _, newURL in
            placementController.updateDocumentURL(newURL)
        }
        .onChange(of: document.locationGeneration) { _, _ in
            placementController.updateDocumentURL(document.publishedFileURL ?? document.fileURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorAddImageClaims)) { note in
            guard let claims = note.userInfo?["claims"] as? [ImageClaim] else { return }
            placementController.handleImageAction(
                claims: claims,
                documentURL: document.publishedFileURL ?? document.fileURL
            )
        }
        .alert(alertTitle, isPresented: alertPresented) {
            Button("OK", role: .cancel) { placementController.alert = nil }
        } message: {
            Text(alertMessage)
        }
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { placementController.alert != nil },
            set: { if !$0 { placementController.alert = nil } }
        )
    }

    private var alertTitle: String {
        switch placementController.alert {
        case .error: return "Couldn’t Add Image"
        case .warning: return "Assets Warning"
        case .info: return "Image Action"
        case nil: return ""
        }
    }

    private var alertMessage: String {
        switch placementController.alert {
        case .error(let m), .warning(let m), .info(let m): return m
        case nil: return ""
        }
    }
}

#Preview {
    ContentView(document: MarkdownDocument())
}
