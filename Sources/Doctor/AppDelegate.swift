import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Set when Finder hands us files at launch, so we don't also restore the
    /// previous session on top of them.
    private var openedFilesAtLaunch = false

    // MARK: - Launch

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Documents open as tabs of one window whatever the system-wide
        // "prefer tabs" setting says; see DocumentWindowController.
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.shared.applyAppearance()

        DispatchQueue.main.async { [weak self] in
            guard let self, !self.openedFilesAtLaunch else { return }
            DocumentStore.shared.restoreSession()
            if DocumentStore.shared.documents.isEmpty {
                DocumentStore.shared.newDocument()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openedFilesAtLaunch = true
        DocumentStore.shared.open(urls: urls)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Clicking the Dock icon with nothing open starts a new document.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            let store = DocumentStore.shared
            if let doc = store.documents.first {
                store.controller(for: doc)?.showWindow(nil)
            } else {
                store.newDocument()
            }
        }
        return true
    }

    /// Doctor behaves like Preview: closing the last window doesn't quit, because
    /// the next file you double-click should open instantly.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Quitting

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let store = DocumentStore.shared
        store.persistSession()

        guard store.hasUnsavedChanges else {
            store.prepareToTerminate()
            return .terminateNow
        }

        let alert = NSAlert()
        let count = store.documents.filter(\.isDirty).count
        alert.messageText = count == 1
            ? "You have one document with unsaved changes."
            : "You have \(count) documents with unsaved changes."
        alert.informativeText = "Doctor reopens unsaved documents next time, but they won't be written to disk."
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            guard store.saveAll() else { return .terminateCancel }
            store.prepareToTerminate()
            return .terminateNow
        case .alertSecondButtonReturn:
            store.prepareToTerminate()
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DocumentStore.shared.persistSession()
    }
}
