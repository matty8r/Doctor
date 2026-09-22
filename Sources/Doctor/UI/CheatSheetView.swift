import AppKit
import SwiftUI

/// The inspector pane: every piece of Markdown Doctor understands, what it looks
/// like, and its shortcut. Clicking a row applies it at the caret, so the sheet
/// is also the slow way to type anything you haven't memorised yet.
struct CheatSheetView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(CheatSheet.sections) { section in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 4)
                        ForEach(section.entries) { entry in
                            CheatSheetRow(entry: entry)
                        }
                    }
                }

                Text("Click a row to insert it. With text selected, it's applied to the selection.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CheatSheetRow: View {
    let entry: CheatSheet.Entry
    @State private var isHovering = false

    var body: some View {
        Button(action: { EditorBridge.shared.perform(entry.apply) }) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.syntax)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                entry.sample
                    .lineLimit(1)
                Text(entry.shortcut ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.07 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Insert \(entry.name)" + (entry.shortcut.map { " (\($0))" } ?? ""))
    }
}

enum CheatSheet {
    struct Section: Identifiable {
        let title: String
        let entries: [Entry]
        var id: String { title }
    }

    struct Entry: Identifiable {
        let name: String
        let syntax: String
        let shortcut: String?
        let sample: AnyView
        let apply: (NSTextView) -> Void
        var id: String { name }

        init(_ name: String, _ syntax: String, _ shortcut: String? = nil,
             sample: some View, apply: @escaping (NSTextView) -> Void) {
            self.name = name
            self.syntax = syntax
            self.shortcut = shortcut
            self.sample = AnyView(sample)
            self.apply = apply
        }
    }

    private static let body = Font.system(size: 13)

    static let sections: [Section] = [
        Section(title: "Text", entries: [
            Entry("bold", "**text**", "⌘B", sample: Text("Bold").font(body).bold()) {
                MarkdownEditing.toggleWrap($0, with: "**")
            },
            Entry("italic", "*text*", "⌘I", sample: Text("Italic").font(body).italic()) {
                MarkdownEditing.toggleWrap($0, with: "*")
            },
            Entry("bold italic", "***text***", sample: Text("Both").font(body).bold().italic()) {
                MarkdownEditing.toggleWrap($0, with: "***")
            },
            Entry("strikethrough", "~~text~~", "⇧⌘X", sample: Text("Struck").font(body).strikethrough()) {
                MarkdownEditing.toggleWrap($0, with: "~~")
            },
            Entry("highlight", "==text==", sample:
                Text("Marked").font(body)
                    .padding(.horizontal, 2)
                    .background(Color.yellow.opacity(0.35), in: RoundedRectangle(cornerRadius: 2))
            ) {
                MarkdownEditing.toggleWrap($0, with: "==")
            },
            Entry("inline code", "`code`", "⌘`", sample:
                Text("code").font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 3)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
            ) {
                MarkdownEditing.toggleWrap($0, with: "`")
            },
        ]),

        Section(title: "Headings", entries: [
            Entry("heading 1", "# Heading", "⌃⌘1", sample: Text("Title").font(.system(size: 17, weight: .bold))) {
                MarkdownEditing.setHeading($0, level: 1)
            },
            Entry("heading 2", "## Heading", "⌃⌘2", sample: Text("Section").font(.system(size: 15, weight: .bold))) {
                MarkdownEditing.setHeading($0, level: 2)
            },
            Entry("heading 3", "### Heading", "⌃⌘3", sample: Text("Subhead").font(.system(size: 13, weight: .semibold))) {
                MarkdownEditing.setHeading($0, level: 3)
            },
        ]),

        Section(title: "Lists", entries: [
            Entry("bulleted list", "- Item", "⇧⌘8", sample: Text("•  Item").font(body)) {
                MarkdownEditing.toggleBulletList($0)
            },
            Entry("numbered list", "1. Item", "⇧⌘7", sample: Text("1.  Item").font(body)) {
                MarkdownEditing.toggleNumberedList($0)
            },
            Entry("task", "- [ ] Task", "⇧⌘9", sample:
                Label("Task", systemImage: "square").font(body).labelStyle(.titleAndIcon)
            ) {
                MarkdownEditing.toggleTaskList($0)
            },
            Entry("nested item", "    - Item", "⌘]", sample: Text("◦  Item").font(body).padding(.leading, 10)) {
                MarkdownEditing.shiftIndent(in: $0, by: 1)
            },
        ]),

        Section(title: "Blocks", entries: [
            Entry("blockquote", "> Quote", "⇧⌘'", sample:
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.secondary.opacity(0.5)).frame(width: 2, height: 14)
                    Text("Quote").font(body).italic().foregroundStyle(.secondary)
                }
            ) {
                MarkdownEditing.toggleBlockquote($0)
            },
            Entry("code block", "```", "⇧⌘K", sample:
                Text("{ }").font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 5)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
            ) {
                MarkdownEditing.insertCodeBlock($0)
            },
            Entry("divider", "---", sample:
                Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 44, height: 1)
            ) {
                MarkdownEditing.insertBlock($0, "---")
            },
            Entry("table", "| A | B |", sample:
                Label("Table", systemImage: "tablecells").font(body).labelStyle(.titleAndIcon)
            ) {
                MarkdownEditing.insertBlock($0, "| Column | Column |\n| --- | --- |\n| Cell | Cell |", select: "Column")
            },
        ]),

        Section(title: "Links", entries: [
            Entry("link", "[text](url)", "⌘K", sample: Text("Link").font(body).underline().foregroundStyle(Color.accentColor)) {
                MarkdownEditing.insertLink($0)
            },
            Entry("image", "![alt](file.png)", sample:
                Label("Image", systemImage: "photo").font(body).labelStyle(.titleAndIcon)
            ) {
                MarkdownEditing.insertInline($0, prefix: "![", placeholder: "description", suffix: "](image.png)")
            },
            Entry("wiki link", "[[Note]]", sample: Text("Note").font(body).foregroundStyle(Color.accentColor)) {
                MarkdownEditing.insertInline($0, prefix: "[[", placeholder: "Note", suffix: "]]")
            },
        ]),
    ]
}
