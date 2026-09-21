import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            TabBar()
            Divider()
            documentArea(for: store.selected)
        }
        .background(Color(nsColor: MarkdownTheme.editorBackground))
        .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: handleDrop)
    }

    @ViewBuilder
    private func documentArea(for document: MarkdownDocument?) -> some View {
        if let document {
            VStack(spacing: 0) {
                if document.hasExternalChanges {
                    ExternalChangeBanner(document: document)
                    Divider()
                }
                MarkdownEditor(document: document, settings: settings)
                Divider()
                StatusBar(document: document)
            }
        } else {
            WelcomeView()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                DispatchQueue.main.async { store.open(url: url) }
            }
        }
        return handled
    }
}

/// Shown when the file changed on disk while there were unsaved edits. Doctor
/// never picks a winner on the user's behalf when both sides have content.
private struct ExternalChangeBanner: View {
    @ObservedObject var document: MarkdownDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text("This file changed on disk")
                    .font(.system(size: 12, weight: .medium))
                Text("You have unsaved edits here too.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Reload from Disk") { document.acceptExternalChanges() }
            Button("Keep My Version") { document.dismissExternalChanges() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.12))
    }
}
