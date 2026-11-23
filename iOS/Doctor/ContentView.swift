import SwiftUI
import SwiftData
import DoctorEditorKit
import DoctorLibrary

/// The library: the CloudKit-backed folders and documents as a tree whose
/// folders collapse and expand (open/closed is remembered on this device
/// only). This is the app's root screen — see docs/ios.md for why there's no
/// tab bar or Files-app browsing the way the "no sync" plan would have had.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query(sort: \Document.modifiedAt, order: .reverse) private var documents: [Document]
    @State private var path: [Document] = []
    @State private var showingSettings = false
    @State private var query = ""
    @StateObject private var expansion = LibraryExpansion()
    @State private var renaming: Folder?
    @State private var renameText = ""
    @State private var deleting: Folder?
    @State private var moving: MoveTarget?
    private let preferences = ReaderPreferences.shared

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if documents.isEmpty && folders.isEmpty {
                    ContentUnavailableView(
                        "No Documents",
                        systemImage: "doc.text",
                        description: Text("Tap + to write one.")
                    )
                } else if isSearching && visibleRootFolders.isEmpty && visibleRootDocuments.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(visibleRootFolders) { folder in
                            folderRow(folder)
                        }
                        ForEach(visibleRootDocuments) { document in
                            documentRow(document)
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
            .searchable(text: $query, prompt: "Search")
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
                    // One "+", as the empty state says ("Tap + to write one"),
                    // with both things you can add inside it.
                    Menu {
                        Button(action: { newDocument(in: nil) }) {
                            Label("New Document", systemImage: "doc.badge.plus")
                        }
                        Button(action: { newFolder(in: nil) }) {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                ReaderSettingsView(preferences: preferences)
            }
            .sheet(item: $moving) { target in
                MoveToFolderView(target: target)
            }
            .alert("Rename Folder", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameText)
                Button("Rename") { commitRename() }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .confirmationDialog(
                "Delete “\(deleting?.displayName ?? "")”?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Folder", role: .destructive) { commitDelete() }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: {
                Text(deleteMessage)
            }
            .onAppear { Persistence.seedIfEmpty(context, title: "Doctor for iPhone", body: Self.sample) }
            .onOpenURL { importDocument(from: $0) }
        }
    }

    // MARK: - Rows

    /// Recursive — a folder's rows include its subfolders' — so it returns
    /// `AnyView` to keep the opaque return type from referring to itself.
    private func folderRow(_ folder: Folder) -> AnyView {
        AnyView(
            DisclosureGroup(isExpanded: isSearching ? .constant(true) : expansion.binding(for: folder.id)) {
                ForEach(visibleChildren(of: folder)) { child in
                    folderRow(child)
                }
                ForEach(visibleDocuments(in: folder)) { document in
                    documentRow(document)
                }
            } label: {
                HStack {
                    Label {
                        Text(folder.displayName)
                    } icon: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color(uiColor: MarkdownTheme.folderTint))
                    }
                    Spacer()
                    Text("\(folder.itemCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .swipeActions {
                    Button("Delete", role: .destructive) { deleting = folder }
                    Button("Move") { moving = .folder(folder) }.tint(.indigo)
                }
                .contextMenu {
                    Button { newDocument(in: folder) } label: {
                        Label("New Document Here", systemImage: "doc.badge.plus")
                    }
                    Button { newFolder(in: folder) } label: {
                        Label("New Folder Here", systemImage: "folder.badge.plus")
                    }
                    Divider()
                    Button { beginRename(folder) } label: {
                        Label("Rename…", systemImage: "pencil")
                    }
                    Button { moving = .folder(folder) } label: {
                        Label("Move to…", systemImage: "folder")
                    }
                    Divider()
                    Button(role: .destructive) { deleting = folder } label: {
                        Label("Delete Folder…", systemImage: "trash")
                    }
                }
            }
        )
    }

    private func documentRow(_ document: Document) -> some View {
        NavigationLink(value: document) {
            row(for: document)
        }
        .swipeActions {
            Button("Delete", role: .destructive) { delete(document) }
            Button("Move") { moving = .document(document) }.tint(.indigo)
        }
        .contextMenu {
            Button { moving = .document(document) } label: {
                Label("Move to…", systemImage: "folder")
            }
            Button(role: .destructive) { delete(document) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
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

    // MARK: - Filtering (the matching rules live in DoctorLibrary, shared with the Mac)

    private var visibleRootFolders: [Folder] {
        Folder.roots(in: folders).filter { $0.isVisible(for: query) }
    }

    private var visibleRootDocuments: [Document] {
        documents.filter { $0.folder == nil && $0.matches(query) }
    }

    private func visibleChildren(of folder: Folder) -> [Folder] {
        folder.sortedChildren.filter { $0.isVisible(for: query) }
    }

    private func visibleDocuments(in folder: Folder) -> [Document] {
        folder.sortedDocuments.filter { $0.matches(query) }
    }

    // MARK: - Actions

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

    /// Creates the document and navigates straight into it — there's no
    /// intermediate compose sheet to open instead, the detail screen
    /// *is* where you write.
    private func newDocument(in folder: Folder?) {
        if let folder { expansion.expanded.insert(folder.id) }
        let document = Document(folder: folder)
        context.insert(document)
        path.append(document)
    }

    private func newFolder(in parent: Folder?) {
        if let parent { expansion.expanded.insert(parent.id) }
        let folder = Folder(name: "New Folder", parent: parent)
        context.insert(folder)
        try? context.save()
        beginRename(folder)
    }

    private func beginRename(_ folder: Folder) {
        renameText = folder.name
        renaming = folder
    }

    private func commitRename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let folder = renaming, !name.isEmpty { folder.name = name }
        try? context.save()
        renaming = nil
    }

    private func commitDelete() {
        deleting?.delete(in: context)
        try? context.save()
        deleting = nil
    }

    private var deleteMessage: String {
        guard let folder = deleting else { return "" }
        let count = folder.itemCount
        let destination = folder.parent?.displayName ?? "the library"
        return count == 0
            ? "The folder is empty."
            : "Its \(count) item\(count == 1 ? "" : "s") will move to \(destination). No documents are deleted."
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
