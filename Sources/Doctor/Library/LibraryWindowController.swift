import AppKit
import SwiftData
import SwiftUI

/// The library's own window: one, separate from the document tabs, so browsing
/// the synced library never disturbs the files you have open.
@MainActor
final class LibraryWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
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

        let toolbar = NSToolbar(identifier: "Doctor.library")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified

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

    /// Menu bar and toolbar entry points: bring the library forward and ask the
    /// tree to make something in the selected folder (or at the top level).
    func newFolder() { show(); ui.command = .newFolder }
    func newDocument() { show(); ui.command = .newDocument }

    @objc private func newFolderAction(_ sender: Any?) { newFolder() }
    @objc private func newDocumentAction(_ sender: Any?) { newDocument() }

    // MARK: - Toolbar

    private enum Item {
        static let newDocument = NSToolbarItem.Identifier("Doctor.library.newDocument")
        static let newFolder = NSToolbarItem.Identifier("Doctor.library.newFolder")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.newFolder, Item.newDocument, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.newFolder, Item.newDocument, .flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.target = self
        item.isBordered = true
        switch identifier {
        case Item.newFolder:
            item.label = "New Folder"
            item.toolTip = "New folder (⇧⌘N) — inside the selected folder, if one is selected"
            item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "New Folder")
            item.action = #selector(newFolderAction(_:))
        case Item.newDocument:
            item.label = "New Document"
            item.toolTip = "New library document (⌥⌘N)"
            item.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "New Document")
            item.action = #selector(newDocumentAction(_:))
        default:
            return nil
        }
        return item
    }

    func toggle() {
        if let window, window.isVisible, window.isKeyWindow {
            window.performClose(nil)
        } else {
            show()
        }
    }
}
