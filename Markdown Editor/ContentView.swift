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
    @StateObject private var actionRouter = EditorActionRouter()
    @StateObject private var commandController = EditorCommandController()
    @StateObject private var toolbarController = EditorToolbarController()

    var body: some View {
        VStack(spacing: 0) {
            // REQ-052/086: persistent dual TextKit host — both editors live across mode toggles.
            EditorHostView(
                document: document,
                session: session,
                placementController: placementController,
                actionRouter: actionRouter
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
        // COR-30: keyed on the revision, not on the whole document string. `id: document.text`
        // made SwiftUI compare the entire text on the main actor for every keystroke, then
        // cancel and restart the counting task — O(document) work per keystroke, outside every
        // boundary the performance budgets measure.
        .task(id: document.sourceVersion) {
            let snapshot = document.text
            guard let next = await statsComputer.counts(for: snapshot), !Task.isCancelled else { return }
            counts = next
        }
        .onAppear {
            placementController.attach(actions: document)
            placementController.session = session
            placementController.trace = document.trace
            placementController.updateDocumentURL(document.publishedFileURL ?? document.fileURL)
            session.attach(document: document)
            session.imagePicker = OpenPanelImagePicker()
            actionRouter.placement = placementController
            actionRouter.document = document
            actionRouter.session = session
            session.actionRouter = actionRouter
            commandController.bind(
                document: document,
                session: session,
                actionRouter: actionRouter,
                window: commandController.presentingWindow
            )
            toolbarController.commandController = commandController
        }
        .background(
            WindowAccessor { window in
                // Rebind with the window this view really belongs to, then install that window's
                // own toolbar. Ordering is safe either way: onAppear and viewDidMoveToWindow
                // both bind the same document and session.
                commandController.bind(
                    document: document,
                    session: session,
                    actionRouter: actionRouter,
                    window: window
                )
                toolbarController.commandController = commandController
                toolbarController.install(on: window)
            }
        )
        .onChange(of: document.publishedFileURL) { _, newURL in
            placementController.updateDocumentURL(newURL)
        }
        .onChange(of: document.locationGeneration) { _, _ in
            placementController.updateDocumentURL(document.publishedFileURL ?? document.fileURL)
        }
        .onReceive(document.canonicalAssetReferenceUpdates) { _ in
            placementController.canonicalAssetReferencesDidUpdate()
        }
        .onDisappear {
            commandController.cancelLink()
            toolbarController.commandController = nil
            session.detach()
        }
        .alert(alertTitle, isPresented: alertPresented) {
            Button("OK", role: .cancel) { placementController.dismissAlert() }
        } message: {
            Text(alertMessage)
        }
        .focusedValue(\.editorCommandController, commandController)
        .sheet(
            isPresented: Binding(
                get: { commandController.linkSheetPresented },
                set: { if !$0 { commandController.cancelLink() } }
            )
        ) {
            LinkEditorSheet(
                destination: Binding(
                    get: { commandController.linkDestination },
                    set: { commandController.updateLinkDestination($0) }
                ),
                onCommit: { commandController.commitLink(destination: commandController.linkDestination) },
                onCancel: { commandController.cancelLink() }
            )
        }
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { placementController.alert != nil },
            set: { if !$0 { placementController.dismissAlert() } }
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
