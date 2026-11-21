import SwiftUI
import SwiftData
import DoctorLibrary

@main
struct DoctorApp: App {
    private let store = Persistence.makeStore()

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
