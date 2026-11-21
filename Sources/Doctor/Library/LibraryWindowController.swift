import AppKit
import SwiftData
import SwiftUI

/// The library's own window: one, separate from the document tabs, so browsing
/// the synced library never disturbs the files you have open.
@MainActor
final class LibraryWindowController: NSWindowController, NSWindowDelegate {
    static let shared = LibraryWindowController()

    let ui = LibraryUIState()

    private static let frameName = "Doctor.library"

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Library"
        window.minSize = NSSize(width: 240, height: 320)
        // Never fold into the document tab group.
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.isRestorable = false

        super.init(window: window)
        window.delegate = self

        let host = NSHostingController(
            rootView: LibraryView(ui: ui)
                .modelContainer(LibraryStore.shared.container)
        )
        host.sizingOptions = []
        window.contentViewController = host

        if !window.setFrameUsingName(Self.frameName) {
            window.setContentSize(NSSize(width: 300, height: 560))
            window.center()
        }
        window.setFrameAutosaveName(Self.frameName)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Brings the library forward, optionally selecting a document or folder.
    func show(selecting id: UUID? = nil) {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let id { ui.reveal = id }
    }

    func toggle() {
        if let window, window.isVisible, window.isKeyWindow {
            window.performClose(nil)
        } else {
            show()
        }
    }
}
