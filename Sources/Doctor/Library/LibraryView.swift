import SwiftData
import SwiftUI

import DoctorLibrary

/// What a row in the library tree is, for selection and drag-and-drop.
enum LibraryItemID: Hashable {
    case folder(UUID)
    case document(UUID)

    /// The text a drag carries. Plain strings keep drags from ever being
    /// mistaken for the file-URL drops the editor accepts.
    var dragString: String {
        switch self {
        case .folder(let id): return "doctor-folder:\(id.uuidString)"
        case .document(let id): return "doctor-doc:\(id.uuidString)"
        }
    }

    init?(dragString: String) {
        let parts = dragString.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "doctor-folder": self = .folder(id)
        case "doctor-doc": self = .document(id)
        default: return nil
        }
    }
}

/// Selection and "reveal this" requests, shared with the window controller so
/// that other parts of the app (Add to Library) can point at a document.
@MainActor
final class LibraryUIState: ObservableObject {
    @Published var selection: Set<LibraryItemID> = []
    @Published var reveal: UUID?
}

/// Which folders are expanded. A per-device view preference, deliberately kept
/// out of the synced model: collapsing a folder here shouldn't collapse it on
/// the phone.
@MainActor
final class LibraryExpansion: ObservableObject {
    private static let key = "libraryExpandedFolders"

    @Published var expanded: Set<UUID> {
        didSet {
            UserDefaults.standard.set(expanded.map(\.uuidString), forKey: Self.key)
        }
    }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        expanded = Set(saved.compactMap(UUID.init(uuidString:)))
    }

    func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { self.expanded.contains(id) },
            set: { isOpen in
                if isOpen { self.expanded.insert(id) } else { self.expanded.remove(id) }
            }
        )
    }
}

/// The library: folders and documents synced through CloudKit, shown as a tree
/// whose folders collapse. Double-click (or Return) opens a document in the
/// normal editor tab; drag a row onto a folder to file it there.
struct LibraryView: View {
    @ObservedObject var ui: LibraryUIState

    @Environment(\.modelContext) private var context
    @Query(sort: \LibraryFolder.name) private var folders: [LibraryFolder]
    @Query(sort: \LibraryDocument.modifiedAt, order: .reverse) private var documents: [LibraryDocument]

    @StateObject private var expansion = LibraryExpansion()
    @State private var query = ""
    @State private var renaming: LibraryItemID?
    @State private var renameText = ""
    @State private var pendingDelete: LibraryItemID?

    private var library: LibraryStore { LibraryStore.shared }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            List(selection: $ui.selection) {
                ForEach(visibleRootFolders) { folder in
                    folderRow(folder)
                }
                ForEach(visibleRootDocuments) { document in
                    documentRow(document)
                }
            }
            .listStyle(.sidebar)
            .contextMenu(forSelectionType: LibraryItemID.self) { ids in
                menu(for: ids)
            } primaryAction: { ids in
                open(ids)
            }
            // Dropping on empty space files the item at the library root.
            .dropDestination(for: String.self) { items, _ in
                move(items, into: nil)
            }
            .overlay {
                if folders.isEmpty && documents.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray").font(.system(size: 26)).foregroundStyle(.tertiary)
                        Text("Your library is empty").foregroundStyle(.secondary)
                        Text("Documents here sync with Doctor on your other devices.")
                            .font(.caption).foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if isSearching && visibleRootFolders.isEmpty && visibleRootDocuments.isEmpty {
                    Text("No matches").foregroundStyle(.secondary)
                }
            }

            Divider()
            footer
        }
        .frame(minWidth: 240, minHeight: 320)
        .onChange(of: ui.reveal) { _, id in
            guard let id else { return }
            reveal(id)
            ui.reveal = nil
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(deleteMessage)
        }
    }

    // MARK: - Rows

    /// Recursive, so it returns `AnyView`: a folder's row contains the rows of
    /// its subfolders, which are folder rows.
    private func folderRow(_ folder: LibraryFolder) -> AnyView {
        AnyView(
            DisclosureGroup(isExpanded: isSearching ? .constant(true) : expansion.binding(for: folder.id)) {
                ForEach(visibleChildren(of: folder)) { child in
                    folderRow(child)
                }
                ForEach(visibleDocuments(in: folder)) { document in
                    documentRow(document)
                }
            } label: {
                Label(folder.displayName, systemImage: "folder")
            }
            .tag(LibraryItemID.folder(folder.id))
            .draggable(LibraryItemID.folder(folder.id).dragString)
            .dropDestination(for: String.self) { items, _ in
                move(items, into: folder)
            }
        )
    }

    private func documentRow(_ document: LibraryDocument) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(document.displayTitle).lineLimit(1)
            Text(document.modifiedAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .tag(LibraryItemID.document(document.id))
        .draggable(LibraryItemID.document(document.id).dragString)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { newDocument(in: selectedFolder) } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("New document")

            Button { newFolder(in: selectedFolder) } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help("New folder")

            Spacer()

            if !library.isCloudBacked {
                Label("Not syncing", systemImage: "icloud.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("iCloud isn't available to this build, so the library is kept on this Mac only.")
            }
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func menu(for ids: Set<LibraryItemID>) -> some View {
        if ids.isEmpty {
            Button("New Document") { newDocument(in: nil) }
            Button("New Folder") { newFolder(in: nil) }
        } else if ids.count == 1, let id = ids.first {
            switch id {
            case .folder(let folderID):
                if let folder = library.folder(withID: folderID) {
                    Button("New Document in Folder") { newDocument(in: folder) }
                    Button("New Folder in Folder") { newFolder(in: folder) }
                    Divider()
                    Button("Rename…") { beginRename(id, current: folder.name) }
                    if folder.parent != nil {
                        Button("Move to Library Root") { _ = folder.move(to: nil); library.save() }
                    }
                    Divider()
                    Button("Delete Folder…", role: .destructive) { pendingDelete = id }
                }
            case .document(let documentID):
                if let document = library.document(withID: documentID) {
                    Button("Open") { open([id]) }
                    Divider()
                    Button("Rename…") { beginRename(id, current: document.title) }
                    if document.folder != nil {
                        Button("Move to Library Root") { document.folder = nil; library.save() }
                    }
                    Divider()
                    Button("Delete…", role: .destructive) { pendingDelete = id }
                }
            }
        }
    }

    // MARK: - Actions

    private func open(_ ids: Set<LibraryItemID>) {
        for id in ids {
            switch id {
            case .document(let documentID):
                if let document = library.document(withID: documentID) {
                    DocumentStore.shared.openLibrary(document)
                }
            case .folder(let folderID):
                // Return on a folder opens or closes it, like Finder's list view.
                if expansion.expanded.contains(folderID) {
                    expansion.expanded.remove(folderID)
                } else {
                    expansion.expanded.insert(folderID)
                }
            }
        }
    }

    private func newDocument(in folder: LibraryFolder?) {
        if let folder { expansion.expanded.insert(folder.id) }
        DocumentStore.shared.newLibraryDocument(in: folder)
    }

    private func newFolder(in parent: LibraryFolder?) {
        if let parent { expansion.expanded.insert(parent.id) }
        let folder = library.newFolder(in: parent)
        ui.selection = [.folder(folder.id)]
        beginRename(.folder(folder.id), current: folder.name)
    }

    private func beginRename(_ id: LibraryItemID, current: String) {
        renameText = current
        renaming = id
    }

    private func commitRename() {
        guard let id = renaming else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch id {
        case .folder(let folderID):
            if let folder = library.folder(withID: folderID), !name.isEmpty { folder.name = name }
        case .document(let documentID):
            if let document = library.document(withID: documentID) {
                document.title = name
                document.touch()
            }
        }
        library.save()
        renaming = nil
    }

    private func commitDelete() {
        guard let id = pendingDelete else { return }
        switch id {
        case .folder(let folderID):
            if let folder = library.folder(withID: folderID) { library.delete(folder) }
        case .document(let documentID):
            if let document = library.document(withID: documentID) { library.delete(document) }
        }
        ui.selection.remove(id)
        pendingDelete = nil
    }

    @discardableResult
    private func move(_ items: [String], into folder: LibraryFolder?) -> Bool {
        var moved = false
        for string in items {
            switch LibraryItemID(dragString: string) {
            case .document(let id):
                if let document = library.document(withID: id), document.folder?.id != folder?.id {
                    document.folder = folder
                    moved = true
                }
            case .folder(let id):
                if let dragged = library.folder(withID: id), dragged.parent?.id != folder?.id,
                   dragged.move(to: folder) {
                    moved = true
                }
            case nil:
                break
            }
        }
        if moved {
            if let folder { expansion.expanded.insert(folder.id) }
            library.save()
        }
        return moved
    }

    /// Expands every folder above the item and selects it.
    private func reveal(_ id: UUID) {
        var parent: LibraryFolder?
        if let document = library.document(withID: id) {
            ui.selection = [.document(id)]
            parent = document.folder
        } else if let folder = library.folder(withID: id) {
            ui.selection = [.folder(id)]
            parent = folder.parent
        }
        while let folder = parent {
            expansion.expanded.insert(folder.id)
            parent = folder.parent
        }
    }

    /// The folder new items should go into: the selected folder, or the folder
    /// the selected document is filed in.
    private var selectedFolder: LibraryFolder? {
        guard ui.selection.count == 1, let id = ui.selection.first else { return nil }
        switch id {
        case .folder(let folderID): return library.folder(withID: folderID)
        case .document(let documentID): return library.document(withID: documentID)?.folder
        }
    }

    // MARK: - Delete wording

    private var deleteTitle: String {
        switch pendingDelete {
        case .folder(let id):
            return "Delete “\(library.folder(withID: id)?.displayName ?? "folder")”?"
        case .document(let id):
            return "Delete “\(library.document(withID: id)?.displayTitle ?? "document")”?"
        case nil:
            return ""
        }
    }

    private var deleteMessage: String {
        switch pendingDelete {
        case .folder(let id):
            guard let folder = library.folder(withID: id) else { return "" }
            let count = (folder.documents?.count ?? 0) + (folder.children?.count ?? 0)
            let destination = folder.parent?.displayName ?? "the library"
            return count == 0
                ? "The folder is empty."
                : "Its \(count) item\(count == 1 ? "" : "s") will move to \(destination). No documents are deleted."
        case .document:
            return "It will be deleted from every device that syncs this library."
        case nil:
            return ""
        }
    }

    // MARK: - Filtering

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !trimmedQuery.isEmpty }

    // The matching rules live in DoctorLibrary, shared with the iPhone app.
    private func matches(_ document: LibraryDocument) -> Bool { document.matches(trimmedQuery) }
    private func isVisible(_ folder: LibraryFolder) -> Bool { folder.isVisible(for: trimmedQuery) }

    private var visibleRootFolders: [LibraryFolder] {
        folders
            .filter { $0.parent == nil && isVisible($0) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var visibleRootDocuments: [LibraryDocument] {
        documents.filter { $0.folder == nil && matches($0) }
    }

    private func visibleChildren(of folder: LibraryFolder) -> [LibraryFolder] {
        folder.sortedChildren.filter(isVisible)
    }

    private func visibleDocuments(in folder: LibraryFolder) -> [LibraryDocument] {
        folder.sortedDocuments.filter(matches)
    }
}
