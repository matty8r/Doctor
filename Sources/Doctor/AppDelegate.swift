import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Set when Finder hands us files at launch, so we don't also restore the
    /// previous session on top of them.
    private var openedFilesAtLaunch = false

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.shared.applyAppearance()

        DispatchQueue.main.async { [weak self] in
            self?.adjustMenus()
            self?.keepMainWindowAlive()
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
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    /// Doctor behaves like Preview: closing the window doesn't quit, because the
    /// next file you double-click should open instantly.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Quitting

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let store = DocumentStore.shared
        store.persistSession()

        guard store.hasUnsavedChanges else { return .terminateNow }

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
            return store.saveAll() ? .terminateNow : .terminateCancel
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DocumentStore.shared.persistSession()
    }

    // MARK: - Window

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = mainWindow else { return }
        window.makeKeyAndOrderFront(nil)
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) }
    }

    /// Closing the window must not destroy it, or there'd be nothing left to
    /// bring back when the next file is double-clicked.
    private func keepMainWindowAlive() {
        mainWindow?.isReleasedWhenClosed = false
    }

    // MARK: - Menu adjustments

    /// SwiftUI gives the window's Close item ⌘W. In a tabbed editor that's the
    /// wrong thing to close, so the tab takes ⌘W and the window moves to ⇧⌘W.
    @objc private func closeTab(_ sender: Any?) {
        DocumentStore.shared.closeSelected()
    }

    @objc private func closeAllTabs(_ sender: Any?) {
        let store = DocumentStore.shared
        for document in store.documents {
            if !store.close(document) { return }
        }
    }

    private func adjustMenus() {
        guard let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu else { return }

        if let closeItem = fileMenu.items.first(where: { $0.action == #selector(NSWindow.performClose(_:)) }) {
            closeItem.title = "Close Window"
            closeItem.keyEquivalent = "w"
            closeItem.keyEquivalentModifierMask = [.command, .shift]

            let closeTabItem = NSMenuItem(
                title: "Close Tab",
                action: #selector(closeTab(_:)),
                keyEquivalent: "w"
            )
            closeTabItem.keyEquivalentModifierMask = [.command]
            closeTabItem.target = self

            let closeAllItem = NSMenuItem(
                title: "Close All Tabs",
                action: #selector(closeAllTabs(_:)),
                keyEquivalent: "w"
            )
            closeAllItem.keyEquivalentModifierMask = [.command, .option]
            closeAllItem.target = self

            let index = fileMenu.index(of: closeItem)
            fileMenu.insertItem(closeTabItem, at: index)
            fileMenu.insertItem(closeAllItem, at: index + 1)
        }
    }
}
