import SwiftUI

@main
struct DoctorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DocumentStore.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        // Document windows are AppKit windows made by DocumentStore, so they can
        // share a native tab group; see DocumentWindowController. SwiftUI only
        // provides Settings, and the menu bar through `commands`.
        Settings {
            SettingsView()
                .environmentObject(settings)
        }
        .commands {
            DoctorCommands(store: store, settings: settings)
        }
    }
}
