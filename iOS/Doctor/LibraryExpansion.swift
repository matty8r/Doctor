import SwiftUI

/// Which folders are expanded in the library list. A per-device view
/// preference, deliberately kept out of the synced model: collapsing a folder
/// here shouldn't collapse it on the Mac.
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
