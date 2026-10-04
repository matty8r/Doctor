import Foundation
import SwiftData

/// A document in the library. This *is* the file — there's no separate
/// on-disk representation the way macOS Doctor has one; CloudKit's private
/// database is where it lives, full content included. See docs/ios.md's
/// "Sync" decision: like Notes, not like Preview.
///
/// CloudKit-backed `@Model` types must have every property optional or
/// defaulted (no unique constraints, no required-but-uninitialized fields) —
/// CloudKit has no way to enforce either, and SwiftData refuses to open a
/// store that tries. `id` exists for stable `Identifiable`/list-diffing
/// identity; it is not what ties a record to its CloudKit counterpart —
/// SwiftData does that itself, the same as it does for `SyncedSubscription`
/// in Feed Me, Seymour!.
@Model
final class Document {
    var id: UUID = UUID()
    var title: String = ""
    /// The whole Markdown source. Plain `String`, not a `CKAsset`: even a long
    /// note is a few hundred KB at most, well inside what a CloudKit record
    /// field holds comfortably, and CloudKit externalizes large field values
    /// to its own asset storage automatically if one ever got there.
    var body: String = ""
    var createdAt: Date = Date()
    /// Last-writer-wins clock. SwiftData's CloudKit backing resolves a
    /// genuine two-device conflict at the whole-record level on its own
    /// (it's built on `NSPersistentCloudKitContainer`, same as Core Data) —
    /// there's no manual merge layer here, and for a single person's own
    /// notes, "whichever device saved last wins" is the right default rather
    /// than attempting a real text merge.
    var modifiedAt: Date = Date()

    init(title: String = "", body: String = "") {
        self.title = title
        self.body = body
    }

    /// What the list shows when there's no title yet — the compose sheet
    /// doesn't require one before you've started typing.
    var displayTitle: String {
        title.isEmpty ? "Untitled" : title
    }

    func touch() {
        modifiedAt = Date()
    }
}
