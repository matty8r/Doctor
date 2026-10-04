import SwiftUI
import SwiftData

/// Plain text in, nothing more — not an editor in the `MarkdownEditing` sense
/// (no formatting commands, no live concealment, no syntax highlighting while
/// typing). It exists only so the library has a way to get content into it
/// without a share extension yet. The reading experience, where the actual
/// engine work went, is `ReaderView`/`DocumentDetailView`. See docs/ios.md —
/// this is deliberately not the "editing on a phone" problem that doc defers.
struct ComposeView: View {
    @Bindable var document: Document
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Title", text: $document.title)
                    .font(.title2.bold())
                    .padding()
                    .focused($titleFocused)
                Divider()
                TextEditor(text: $document.body)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 12)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                }
            }
            .onAppear {
                if document.title.isEmpty { titleFocused = true }
            }
        }
    }

    private func finish() {
        document.touch()
        try? context.save()
        dismiss()
    }
}

#Preview {
    let container = Persistence.makeInMemoryContainer()
    let document = Document(title: "A note", body: "Some *text*.")
    container.mainContext.insert(document)
    return ComposeView(document: document)
        .modelContainer(container)
}
