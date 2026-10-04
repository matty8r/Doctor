import SwiftUI
import SwiftData

/// The library: every document in the CloudKit-backed store, newest-edited
/// first. This is the app's root screen — see docs/ios.md for why there's no
/// tab bar or Files-app browsing the way the "no sync" plan would have had.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Document.modifiedAt, order: .reverse) private var documents: [Document]
    @State private var composing: Document?

    var body: some View {
        Group {
            if documents.isEmpty {
                ContentUnavailableView(
                    "No Documents",
                    systemImage: "doc.text",
                    description: Text("Tap + to write one.")
                )
            } else {
                List {
                    ForEach(documents) { document in
                        NavigationLink(value: document) {
                            row(for: document)
                        }
                        .swipeActions {
                            Button("Edit") { composing = document }.tint(.blue)
                            Button("Delete", role: .destructive) { delete(document) }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Doctor")
        // Centered at the top, matching Feed Me, Seymour! and Sidetable's own
        // SidebarView convention — .inline centers; the default .large mode
        // left-aligns a big title instead.
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Document.self) { document in
            DocumentDetailView(document: document)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: newDocument) {
                    Label("New Document", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(item: $composing) { document in
            ComposeView(document: document)
        }
        .onAppear { Persistence.seedIfEmpty(context) }
    }

    private func row(for document: Document) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(document.displayTitle)
                .font(.headline)
                .lineLimit(1)
            Text(document.modifiedAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func newDocument() {
        let document = Document()
        context.insert(document)
        composing = document
    }

    private func delete(_ document: Document) {
        context.delete(document)
    }

    /// Exercises the table/code-block/rule fixes from Doctor 1.2/1.2.1 on
    /// macOS, same as it did before the library existed — see the commit that
    /// first proved `DoctorEditorKit` rendering on a real device.
    static let sample = """
    # Doctor for iPhone

    This is the shared rendering engine — the same theme, the same syntax \
    highlighter, the same table layout — running on iOS.

    ---

    ## What it proves

    **Bold**, *italic*, and `inline code` all carry over, along with tables:

    | Piece | Status |
    | --- | --- |
    | Markdown engine | Free |
    | Theme + highlighter | Shimmed |
    | Layout manager | Ported |
    | CloudKit library | Here |
    | Editing | Plain text only — v1 reads |

    A fenced block, to check the panel sits snugly around it:

    ```swift
    let engine = "DoctorEditorKit"
    print("shared with \\(engine)")
    ```

    - A list item
    - Another, with **emphasis**
      - Nested one step

    > A blockquote, to check the bar renders where it should.
    """
}

#Preview {
    NavigationStack { ContentView() }
        .modelContainer(Persistence.makeInMemoryContainer())
}
