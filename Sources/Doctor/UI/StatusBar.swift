import AppKit
import SwiftUI

struct StatusBar: View {
    @ObservedObject var document: MarkdownDocument
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 10) {
            modePicker

            Divider().frame(height: 14)

            Text(statistics)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer(minLength: 12)

            if settings.isObsidianConfigured {
                Button(action: { ObsidianService.send(document) }) {
                    Label("Obsidian", systemImage: "square.stack.3d.up")
                        .font(.system(size: 11))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy into your vault and open it in Obsidian (⇧⌘O)")
            }

            Text(location)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
                .help(document.url?.path ?? "This document hasn't been saved yet")
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Color(nsColor: MarkdownTheme.chrome))
    }

    private var modePicker: some View {
        Picker("", selection: Binding(
            get: { document.mode },
            set: { document.mode = $0 }
        )) {
            ForEach(EditorMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 148)
        .controlSize(.small)
    }

    private var statistics: String {
        let words = document.wordCount
        let parts = [
            "\(words) word\(words == 1 ? "" : "s")",
            "\(document.characterCount) char\(document.characterCount == 1 ? "" : "s")",
            "\(document.readingMinutes) min read"
        ]
        return parts.joined(separator: "  ·  ")
    }

    private var location: String {
        guard let url = document.url else { return "Unsaved" }
        return url.deletingLastPathComponent().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
