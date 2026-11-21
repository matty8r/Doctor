import SwiftUI
import SwiftData
import DoctorLibrary

/// The library: every document in the CloudKit-backed store, newest-edited
/// first. This is the app's root screen — see docs/ios.md for why there's no
/// tab bar or Files-app browsing the way the "no sync" plan would have had.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Document.modifiedAt, order: .reverse) private var documents: [Document]
    @State private var path: [Document] = []
    @State private var showingSettings = false
    private let preferences = ReaderPreferences.shared

    var body: some View {
        NavigationStack(path: $path) {
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
                                Button("Delete", role: .destructive) { delete(document) }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Doctor")
            // Centered at the top, matching Feed Me, Seymour! and Sidetable's
            // own SidebarView convention — .inline centers; the default
            // .large mode left-aligns a big title instead.
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Document.self) { document in
                DocumentDetailView(document: document)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Label("Reading Settings", systemImage: "textformat.size")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: newDocument) {
                        Label("New Document", systemImage: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                ReaderSettingsView(preferences: preferences)
            }
            .onAppear { Persistence.seedIfEmpty(context, title: "Doctor for iPhone", body: Self.sample) }
            .onOpenURL { importDocument(from: $0) }
        }
    }

    /// Doctor is an importer, not a file-based editor like the Mac app: Open
    /// With hands over a URL to read once, not a file to keep a live link to
    /// (see docs/ios.md's "Sync" decision — like Notes, not like Preview).
    /// This copies that file's content into a new library document and
    /// navigates straight into it, the same as writing a new one.
    private func importDocument(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let title = url.deletingPathExtension().lastPathComponent
        let body = (try? String(contentsOf: url, encoding: .utf8))
            ?? "Couldn't read \"\(url.lastPathComponent)\" as text."
        let document = Document(title: title, body: body)
        context.insert(document)
        path.append(document)
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

    /// Creates the document and navigates straight into it — there's no
    /// intermediate compose sheet to open instead, the detail screen
    /// *is* where you write.
    private func newDocument() {
        let document = Document()
        context.insert(document)
        path.append(document)
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
    highlighter, the same table layout — running on iOS. Tap anywhere in \
    this text to edit it; the line you're on shows its raw Markdown, every \
    other line stays rendered.

    ---

    ## What it proves

    **Bold**, *italic*, and `inline code` all carry over, along with tables:

    | Piece | Status |
    | --- | --- |
    | Markdown engine | Free |
    | Theme + highlighter | Shimmed |
    | Layout manager | Ported |
    | CloudKit library | Here |
    | Editing in place | Here |

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
    ContentView()
        .modelContainer(Persistence.makeInMemoryContainer())
}
