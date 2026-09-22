import AppKit
import SwiftUI

/// The menu bar. Anything you can do with the mouse should have a menu item and
/// a key equivalent; this is where that contract lives.
struct DoctorCommands: Commands {
    @ObservedObject var store: DocumentStore
    @ObservedObject var settings: AppSettings

    private var document: MarkdownDocument? { store.selected }
    private var hasDocument: Bool { store.selected != nil }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { store.newDocument() }
                .keyboardShortcut("n", modifiers: .command)

            Button("Open…") { store.showOpenPanel() }
                .keyboardShortcut("o", modifiers: .command)

            Menu("Open Recent") {
                ForEach(settings.recentFiles, id: \.path) { url in
                    Button(url.lastPathComponent) { store.open(url: url) }
                }
                if !settings.recentFiles.isEmpty {
                    Divider()
                    Button("Clear Menu") { settings.clearRecentFiles() }
                }
            }
            .disabled(settings.recentFiles.isEmpty)
        }

        CommandGroup(replacing: .saveItem) {
            // Replacing this group also removes SwiftUI's Close, so it lives here.
            // ⌘W closes the document in front, which is its tab when there are
            // several; ⇧⌘W closes the window and every tab in it.
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: .command)

            Button("Close Window") { store.closeWindow() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!hasDocument)

            Divider()

            Button("Save") { store.saveSelected() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!hasDocument)

            Button("Save As…") { if let document { store.saveAs(document) } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!hasDocument)

            Button("Revert to Saved") {
                guard let document, document.url != nil else { return }
                try? document.revert()
            }
            .disabled(document?.url == nil)

            Divider()

            Menu("Export") {
                Button("PDF…") {
                    if let document {
                        ExportService.exportPDF(document, in: store.selectedController?.window)
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("HTML…") {
                    if let document { ExportService.exportHTML(document) }
                }

                Button("Copy as HTML") {
                    if let document { ExportService.copyHTMLToPasteboard(document) }
                }
            }
            .disabled(!hasDocument)

            Button("Send to Obsidian") {
                if let document { ObsidianService.send(document) }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(!hasDocument)

            Divider()

            Button("Reveal in Finder") {
                guard let url = document?.url else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .disabled(document?.url == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") {
                if let document {
                    ExportService.printDocument(document, in: store.selectedController?.window)
                }
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(!hasDocument)
        }

        CommandGroup(after: .toolbar) {
            Button("Preview") { document?.mode = .preview }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(!hasDocument)

            Button("Source") { document?.mode = .source }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(!hasDocument)

            Button("Toggle View") { document?.mode = document?.mode.toggled ?? .preview }
                .keyboardShortcut("/", modifiers: .command)
                .disabled(!hasDocument)

            Divider()

            Button(store.selectedController?.isCheatSheetVisible == true ? "Hide Cheat Sheet" : "Show Cheat Sheet") {
                store.selectedController?.toggleCheatSheet()
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            .disabled(!hasDocument)

            Divider()

            Button("Actual Size") { settings.previewFontSize = 16 }
                .keyboardShortcut("0", modifiers: .command)
            Button("Zoom In") { settings.previewFontSize = min(28, settings.previewFontSize + 1) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { settings.previewFontSize = max(10, settings.previewFontSize - 1) }
                .keyboardShortcut("-", modifiers: .command)

            Divider()
        }

        CommandMenu("Format") {
            Button("Bold") { EditorBridge.shared.perform { MarkdownEditing.toggleWrap($0, with: "**") } }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { EditorBridge.shared.perform { MarkdownEditing.toggleWrap($0, with: "*") } }
                .keyboardShortcut("i", modifiers: .command)
            Button("Strikethrough") { EditorBridge.shared.perform { MarkdownEditing.toggleWrap($0, with: "~~") } }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Inline Code") { EditorBridge.shared.perform { MarkdownEditing.toggleWrap($0, with: "`") } }
                .keyboardShortcut("`", modifiers: .command)
            Button("Code Block") { EditorBridge.shared.perform(MarkdownEditing.insertCodeBlock) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Link…") { EditorBridge.shared.perform(MarkdownEditing.insertLink) }
                .keyboardShortcut("k", modifiers: .command)

            Divider()

            Menu("Heading") {
                ForEach(1...6, id: \.self) { level in
                    Button("Heading \(level)") {
                        EditorBridge.shared.perform { MarkdownEditing.setHeading($0, level: level) }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(level)")), modifiers: [.command, .control])
                }
                Divider()
                Button("Body Text") {
                    EditorBridge.shared.perform { MarkdownEditing.setHeading($0, level: 0) }
                }
                .keyboardShortcut("0", modifiers: [.command, .control])
            }

            Menu("List") {
                Button("Bulleted") { EditorBridge.shared.perform(MarkdownEditing.toggleBulletList) }
                    .keyboardShortcut("8", modifiers: [.command, .shift])
                Button("Numbered") { EditorBridge.shared.perform(MarkdownEditing.toggleNumberedList) }
                    .keyboardShortcut("7", modifiers: [.command, .shift])
                Button("Task") { EditorBridge.shared.perform(MarkdownEditing.toggleTaskList) }
                    .keyboardShortcut("9", modifiers: [.command, .shift])
            }

            Button("Blockquote") { EditorBridge.shared.perform(MarkdownEditing.toggleBlockquote) }
                .keyboardShortcut("'", modifiers: [.command, .shift])

            Divider()

            Button("Indent") { EditorBridge.shared.perform { MarkdownEditing.shiftIndent(in: $0, by: 1) } }
                .keyboardShortcut("]", modifiers: .command)
            Button("Outdent") { EditorBridge.shared.perform { MarkdownEditing.shiftIndent(in: $0, by: -1) } }
                .keyboardShortcut("[", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button("Doctor Help") {
                DocumentStore.shared.presentMessage(
                    "Doctor",
                    detail: """
                    Preview and Source are both editable — Preview just hides the \
                    punctuation on lines you aren't working on.

                    Cmd-click follows a link. Clicking a checkbox ticks it. \
                    Print and Export render the document properly, so what you get \
                    on paper is not what's in the editor.
                    """
                )
            }
        }
    }
}
