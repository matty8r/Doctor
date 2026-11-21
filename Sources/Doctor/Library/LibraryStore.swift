import Foundation
import SwiftData

import DoctorLibrary

/// Owns the synced library's SwiftData container on the Mac — the same
/// `Document`/`Folder` schema, in the same CloudKit container, as the iPhone
/// app (both open it through `DoctorLibrary.Persistence`).
///
/// Everything here is main-actor: SwiftData's `mainContext` is, and the
/// library window's `@Query` reads from the same one, so an edit made in an
/// open tab shows up in the sidebar without any plumbing.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    let container: ModelContainer
    /// False when CloudKit couldn't be opened — an ad-hoc-signed development
    /// build, no iCloud account, or no provisioning profile. The library still
    /// works and keeps everything on this Mac; the library window says so.
    let isCloudBacked: Bool

    var context: ModelContext { container.mainContext }

    private init() {
        let store = Persistence.makeStore()
        container = store.container
        isCloudBacked = store.isCloudBacked
    }

    // MARK: - Lookup

    func document(withID id: UUID) -> LibraryDocument? {
        var descriptor = FetchDescriptor<LibraryDocument>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func folder(withID id: UUID) -> LibraryFolder? {
        var descriptor = FetchDescriptor<LibraryFolder>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Creating and changing

    @discardableResult
    func newDocument(title: String = "", body: String = "", in folder: LibraryFolder? = nil) -> LibraryDocument {
        let document = LibraryDocument(title: title, body: body, folder: folder)
        context.insert(document)
        save()
        return document
    }

    @discardableResult
    func newFolder(named name: String = "New Folder", in parent: LibraryFolder? = nil) -> LibraryFolder {
        let folder = LibraryFolder(name: name, parent: parent)
        context.insert(folder)
        save()
        return folder
    }

    func delete(_ document: LibraryDocument) {
        context.delete(document)
        save()
    }

    func delete(_ folder: LibraryFolder) {
        folder.delete(in: context)
        save()
    }

    func save() {
        guard context.hasChanges else { return }
        do { try context.save() } catch { NSLog("Doctor: library save failed: \(error)") }
    }

    /// "Library / Work / Drafts" — where a document is filed, for the window subtitle.
    func path(of document: LibraryDocument) -> String {
        var names: [String] = []
        var cursor = document.folder
        while let folder = cursor {
            names.insert(folder.displayName, at: 0)
            cursor = folder.parent
        }
        return (["Library"] + names).joined(separator: " / ")
    }
}
