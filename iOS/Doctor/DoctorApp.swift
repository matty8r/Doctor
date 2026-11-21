import SwiftUI
import SwiftData
import DoctorLibrary

@main
struct DoctorApp: App {
    private let store = Self.makeLibraryStore()

    private static func makeLibraryStore() -> Persistence.Store {
        #if DEBUG
        if SampleLibrary.requested {
            return Persistence.Store(container: SampleLibrary.makeContainer(), isCloudBacked: false)
        }
        #endif
        return Persistence.makeStore()
    }

    var body: some Scene {
        WindowGroup {
            // Owns its own NavigationStack (and the path binding newDocument()
            // pushes into), rather than one wrapped around it here.
            ContentView()
                #if DEBUG
                .task {
                    if SchemaSeed.requested { await SchemaSeed.run(store.container.mainContext) }
                }
                #endif
        }
        .modelContainer(store.container)
    }
}
