import Foundation
import SwiftData

/// A folder in the library. Folders nest to any depth; `parent == nil` is the
/// library root. Syncs through CloudKit with `Document`, so it follows the
/// same rules: every property defaulted or optional, every relationship
/// optional with a declared inverse.
///
/// Whether a folder is expanded or collapsed in a sidebar is deliberately
/// *not* stored here — that's a per-device view preference, and collapsing a
/// folder on the Mac shouldn't collapse it on the phone.
@Model
public final class Folder {
    public var id: UUID = UUID()
    public var name: String = ""
    public var createdAt: Date = Date()

    public var parent: Folder?

    // `.nullify` is the delete rule SwiftData applies on its own when a
    // folder is removed; `Folder.delete(in:)` re-files the contents into the
    // parent first so nothing is ever orphaned to the root by accident.
    @Relationship(deleteRule: .nullify, inverse: \Folder.parent)
    public var children: [Folder]? = []

    @Relationship(deleteRule: .nullify, inverse: \Document.folder)
    public var documents: [Document]? = []

    public init(name: String = "", parent: Folder? = nil) {
        self.name = name
        self.parent = parent
    }

    public var displayName: String {
        name.isEmpty ? "Untitled Folder" : name
    }

    /// Subfolders, alphabetically.
    public var sortedChildren: [Folder] {
        (children ?? []).sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    /// Documents filed directly here, most recently edited first.
    public var sortedDocuments: [Document] {
        (documents ?? []).sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// True if `other` is this folder or sits anywhere beneath it. A folder
    /// must not be moved into itself or its own descendants.
    public func contains(_ other: Folder) -> Bool {
        var cursor: Folder? = other
        while let current = cursor {
            if current.id == id { return true }
            cursor = current.parent
        }
        return false
    }

    /// Moves this folder under `newParent` (`nil` = root). Refuses a move
    /// that would create a cycle and returns whether it happened.
    @discardableResult
    public func move(to newParent: Folder?) -> Bool {
        if let newParent, contains(newParent) { return false }
        parent = newParent
        return true
    }

    /// Deletes the folder, re-filing its documents and subfolders into its
    /// parent (or the root) first — deleting a folder never deletes notes.
    public func delete(in context: ModelContext) {
        for document in documents ?? [] { document.folder = parent }
        for child in children ?? [] { child.parent = parent }
        context.delete(self)
    }
}

// MARK: - Searching and counting (shared by the Mac and iPhone library views)

extension Document {
    /// Whether this document matches a search `query` (title or body). An
    /// empty query matches everything.
    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty
            || displayTitle.localizedCaseInsensitiveContains(q)
            || body.localizedCaseInsensitiveContains(q)
    }
}

extension Folder {
    /// Whether this folder should show while searching: its own name matches,
    /// or a document or subfolder inside it does. An empty query shows all.
    public func isVisible(for query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty
            || displayName.localizedCaseInsensitiveContains(q)
            || (documents ?? []).contains { $0.matches(q) }
            || (children ?? []).contains { $0.isVisible(for: q) }
    }

    /// Documents and subfolders directly inside.
    public var itemCount: Int {
        (documents?.count ?? 0) + (children?.count ?? 0)
    }

    /// Top-level folders from a flat list, alphabetical.
    public static func roots(in folders: [Folder]) -> [Folder] {
        folders
            .filter { $0.parent == nil }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}
