import SwiftUI
import SwiftData

@main
struct DoctorApp: App {
    private let store = Persistence.makeStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
            }
        }
        .modelContainer(store.container)
    }
}
