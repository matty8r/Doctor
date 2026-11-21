#if DEBUG
import Foundation
import SwiftData
import DoctorLibrary

/// Registers the `Folder` record type (and `Document.folder`) in CloudKit's
/// *development* schema, so it can then be deployed to Production from the
/// CloudKit dashboard.
///
/// CloudKit only creates a record type or field when a development-signed
/// build saves a record that uses it, and nothing in the iPhone UI makes a
/// folder yet. Launch a Debug build with the argument `-SeedCloudKitSchema`
/// and it saves one folder tree with a document filed in it, waits for the
/// mirroring export, deletes them all again, waits for that to export too,
/// and exits. The record types stay behind; the sample records don't.
///
/// Debug builds only: a Release build is Production-environment and can't
/// create schema, and shouldn't carry this at all.
enum SchemaSeed {
    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains("-SeedCloudKitSchema")
    }

    @MainActor
    static func run(_ context: ModelContext) async {
        NSLog("SchemaSeed: creating sample folder and document")
        let parent = Folder(name: "Schema seed")
        let child = Folder(name: "Schema seed child", parent: parent)
        let document = Document(
            title: "Schema seed",
            body: "Created to register the Folder record type in CloudKit's development schema. Safe to delete.",
            folder: child
        )
        context.insert(parent)
        context.insert(child)
        context.insert(document)
        do { try context.save() } catch { NSLog("SchemaSeed: save failed: \(error)") }

        // Mirroring exports on its own schedule; give it time to push.
        try? await Task.sleep(for: .seconds(60))

        NSLog("SchemaSeed: removing the sample records")
        context.delete(document)
        context.delete(child)
        context.delete(parent)
        do { try context.save() } catch { NSLog("SchemaSeed: cleanup save failed: \(error)") }
        try? await Task.sleep(for: .seconds(30))

        NSLog("SchemaSeed: done")
        exit(0)
    }
}

/// `-SampleLibrary`: an in-memory library with a few folders and documents,
/// for looking at the library screen (simulator, screenshots) without touching
/// the real store or CloudKit. Nothing is saved anywhere.
enum SampleLibrary {
    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains("-SampleLibrary")
    }

    @MainActor
    static func makeContainer() -> ModelContainer {
        let container = Persistence.makeInMemoryContainer()
        let context = container.mainContext
        let work = Folder(name: "Work")
        let drafts = Folder(name: "Drafts", parent: work)
        let meetings = Folder(name: "Meetings", parent: work)
        let personal = Folder(name: "Personal")
        let recipes = Folder(name: "Recipes", parent: personal)
        [work, drafts, meetings, personal, recipes].forEach(context.insert)

        func doc(_ title: String, _ folder: Folder?, _ ago: TimeInterval) {
            let d = Document(title: title, body: "# \(title)\n", folder: folder)
            d.modifiedAt = Date().addingTimeInterval(-ago)
            context.insert(d)
        }
        doc("Doctor for iPhone", nil, 300)
        doc("Reading list", nil, 86_400 * 3)
        doc("Q4 plan", work, 3_600)
        doc("Launch notes", drafts, 7_200)
        doc("Essay: on plain text", drafts, 86_400)
        doc("Weekly sync", meetings, 86_400 * 2)
        doc("Pasta", recipes, 86_400 * 9)
        doc("Packing list", personal, 86_400 * 5)
        try? context.save()

        // Work and Drafts open, Personal collapsed — the tree in both states.
        UserDefaults.standard.set([work.id.uuidString, drafts.id.uuidString], forKey: "libraryExpandedFolders")
        return container
    }
}
#endif
