import SwiftUI

@main
struct DoctorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DocumentStore.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        // A single window, not a WindowGroup: Doctor's tabs live inside one
        // window, so ⌘N should make a tab rather than another copy of the app.
        Window("Doctor", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .frame(minWidth: 620, minHeight: 400)
        }
        .defaultSize(width: 1020, height: 740)
        .windowStyle(.hiddenTitleBar)
        .commands {
            DoctorCommands(store: store, settings: settings)
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}
