import Foundation
import SwiftData

/// Sets up the one CloudKit-backed store the library lives in, shared by the
/// iOS and macOS apps.
/// Modeled on
/// Feed Me, Seymour!'s `Persistence.swift` — same fallback ladder, same
/// reason for it — but a single configuration: Doctor has no local-only
/// split, because there's no part of a `Document` that isn't worth syncing
/// (unlike an article body that's re-fetchable from its feed, a note has no
/// other copy anywhere).
public enum Persistence {

    public static let schema = Schema([Document.self, Folder.self])

    public struct Store {
        public var container: ModelContainer
        /// False when the CloudKit-backed configuration couldn't be opened —
        /// no entitlement, no signed-in iCloud account, or (today) no
        /// container provisioned yet on the Developer Portal. The library
        /// still works; it just doesn't leave the device until that's fixed.
        public var isCloudBacked: Bool
    }

    public static func makeStore() -> Store {
        let cloud = ModelConfiguration("DoctorLibrary", schema: schema, cloudKitDatabase: .automatic)
        do {
            let container = try ModelContainer(for: schema, configurations: cloud)
            return Store(container: container, isCloudBacked: true)
        } catch {
            // Say why — the fallback is silent to the person using the app, and
            // "it just isn't syncing" is otherwise a guessing game.
            NSLog("Doctor: CloudKit-backed library failed to open, falling back to local only: \(error)")
        }

        let offline = ModelConfiguration("DoctorLibrary", schema: schema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: offline) {
            return Store(container: container, isCloudBacked: false)
        }

        // A store that won't open at all is worse than no store: fall back to
        // memory so the app still launches rather than crashing at startup.
        assertionFailure("Falling back to an in-memory store")
        let memory = try! ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        return Store(container: memory, isCloudBacked: false)
    }

    /// Previews and tests. Local only, so nothing touches a real iCloud account.
    public static func makeInMemoryContainer() -> ModelContainer {
        try! ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    /// A fresh install, or a device that hasn't synced yet, is an empty
    /// library — seed one document so there's something to read and the
    /// rendering engine is exercised without typing anything first. Deletable
    /// like any other document, and never reappears once the library has
    /// anything in it (including something still inbound from iCloud).
    @MainActor
    public static func seedIfEmpty(_ context: ModelContext, title: String, body: String) {
        let existing = (try? context.fetchCount(FetchDescriptor<Document>())) ?? 0
        guard existing == 0 else { return }
        context.insert(Document(title: title, body: body))
        try? context.save()
    }
}
