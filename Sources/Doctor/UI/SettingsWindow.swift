import AppKit

/// Opening the Settings scene from code needs a different selector depending on
/// the macOS version, and neither is public API. Try both, fail quietly.
enum SettingsWindow {
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        let candidates = ["showSettingsWindow:", "showPreferencesWindow:"]
        for name in candidates {
            let selector = Selector(name)
            if NSApp.sendAction(selector, to: nil, from: nil) { return }
        }
    }
}
