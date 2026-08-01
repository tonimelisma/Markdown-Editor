//
//  LinkEditorSheet.swift
//  Markdown Editor
//

import SwiftUI

struct LinkEditorSheet: View {
    @Binding var destination: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Link").font(.headline)
            TextField("URL (leave empty to remove)", text: $destination)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onCommit).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
