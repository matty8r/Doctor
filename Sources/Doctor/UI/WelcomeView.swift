import AppKit
import SwiftUI

/// What you see with no tabs open. It exists mostly so the app never presents a
/// blank rectangle and leaves you guessing.
struct WelcomeView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 22) {
                header
                actions
                if !settings.recentFiles.isEmpty { recents }
            }
            .frame(maxWidth: 460)

            Spacer()

            Text("Drop a Markdown file anywhere in this window to open it.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: MarkdownTheme.editorBackground))
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Doctor")
                .font(.system(size: 24, weight: .semibold))
            Text("A reader and editor for Markdown files.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("New Document") { store.newDocument() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Open…") { store.showOpenPanel() }
                .keyboardShortcut("o", modifiers: .command)
        }
        .controlSize(.large)
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RECENT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)

            ForEach(settings.recentFiles.prefix(6), id: \.path) { url in
                Button(action: { store.open(url: url) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text(url.lastPathComponent)
                            .font(.system(size: 12))
                        Spacer()
                        Text(url.deletingLastPathComponent().lastPathComponent)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }
        }
        .padding(.top, 8)
    }
}
