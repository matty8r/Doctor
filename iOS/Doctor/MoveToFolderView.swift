import SwiftUI
import SwiftData
import DoctorLibrary

/// What's being filed somewhere else.
enum MoveTarget: Identifiable {
    case document(Document)
    case folder(Folder)

    var id: UUID {
        switch self {
        case .document(let document): return document.id
        case .folder(let folder): return folder.id
        }
    }

    var title: String {
        switch self {
        case .document(let document): return document.displayTitle
        case .folder(let folder): return folder.displayName
        }
    }
}

/// "Move to…": a picker over the whole folder tree. Dragging between rows is
/// unreliable inside a List on iPhone, and this works the same for documents
/// and folders.
struct MoveToFolderView: View {
    let target: MoveTarget

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.name) private var folders: [Folder]

    private var currentParent: Folder? {
        switch target {
        case .document(let document): return document.folder
        case .folder(let folder): return folder.parent
        }
    }

    var body: some View {
        NavigationStack {
            List {
                destinationRow(nil, name: "Library", depth: 0)
                ForEach(Folder.roots(in: folders)) { folder in
                    ForEach(flattened(folder, depth: 0), id: \.folder.id) { entry in
                        destinationRow(entry.folder, name: entry.folder.displayName, depth: entry.depth)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Move “\(target.title)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private struct Entry { let folder: Folder; let depth: Int }

    private func flattened(_ folder: Folder, depth: Int) -> [Entry] {
        [Entry(folder: folder, depth: depth)]
            + folder.sortedChildren.flatMap { flattened($0, depth: depth + 1) }
    }

    /// A folder can't be moved into itself or anything beneath it.
    private func isAllowed(_ destination: Folder?) -> Bool {
        guard case .folder(let moving) = target, let destination else { return true }
        return !moving.contains(destination)
    }

    private func destinationRow(_ destination: Folder?, name: String, depth: Int) -> some View {
        let isCurrent = destination?.id == currentParent?.id
        return Button {
            move(to: destination)
        } label: {
            HStack {
                Label(name, systemImage: destination == nil ? "tray" : "folder")
                    .padding(.leading, CGFloat(depth) * 18)
                Spacer()
                if isCurrent { Image(systemName: "checkmark").foregroundStyle(.secondary) }
            }
        }
        .disabled(!isAllowed(destination) || isCurrent)
    }

    private func move(to destination: Folder?) {
        switch target {
        case .document(let document):
            document.folder = destination
        case .folder(let folder):
            _ = folder.move(to: destination)
        }
        try? context.save()
        dismiss()
    }
}
