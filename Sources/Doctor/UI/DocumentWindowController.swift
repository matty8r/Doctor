import AppKit
import Combine
import SwiftUI

import DoctorEditorKit
/// One window per document. The windows share a tab group, so open files still
/// land beside each other, but the tab bar only appears once there is more than
/// one of them: a single file is just a window, the way Preview does it.
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let markdown: MarkdownDocument
    /// This window's own library selection and pending commands. The sidebar is
    /// per window (each tab is a window); what's shared between them is whether
    /// it is visible and which folders are open.
    let libraryUI: LibraryUIState

    private let split = NSSplitViewController()
    private var libraryItem: NSSplitViewItem!
    private var cheatSheetItem: NSSplitViewItem!
    private weak var modeGroup: NSToolbarItemGroup?
    private var observers: Set<AnyCancellable> = []

    private static let cheatSheetKey = "cheatSheetVisible"
    private static let libraryKey = "librarySidebarVisible"
    private static let libraryVisibilityChanged = Notification.Name("Doctor.librarySidebarVisibilityChanged")
    private static let frameName = "Doctor.document"

    init(markdown: MarkdownDocument) {
        self.markdown = markdown
        self.libraryUI = MainActor.assumeIsolated { LibraryUIState() }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1020, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 620, height: 400)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "Doctor.document"
        window.toolbarStyle = .unified
        // Doctor restores its own session, documents and all; AppKit's window
        // restoration would bring back empty windows alongside it.
        window.isRestorable = false

        super.init(window: window)
        window.delegate = self

        buildContent()
        buildToolbar()
        observeDocument()

        // Assigning the split view controller sizes the window to fit it, which
        // is its minimum; put back the size the last window had, or a default.
        if !window.setFrameUsingName(Self.frameName) {
            window.setContentSize(NSSize(width: 1020, height: 740))
        }
        window.setFrameAutosaveName(Self.frameName)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Content

    private func buildContent() {
        // The library, as a collapsible sidebar on the left. Visible by default
        // the first time; after that the last choice sticks, in every tab.
        let libraryRoot = MainActor.assumeIsolated {
            AnyView(LibraryView(ui: libraryUI).modelContainer(LibraryStore.shared.container))
        }
        let library = NSHostingController(rootView: libraryRoot)
        library.sizingOptions = []
        libraryItem = NSSplitViewItem(sidebarWithViewController: library)
        libraryItem.minimumThickness = 210
        libraryItem.maximumThickness = 420
        libraryItem.canCollapse = true
        libraryItem.isCollapsed = !(UserDefaults.standard.object(forKey: Self.libraryKey) as? Bool ?? true)

        let editor = NSHostingController(
            rootView: DocumentView(document: markdown)
                .environmentObject(DocumentStore.shared)
                .environmentObject(AppSettings.shared)
        )
        editor.sizingOptions = []
        let editorItem = NSSplitViewItem(viewController: editor)
        editorItem.minimumThickness = 380

        let sheet = NSHostingController(rootView: CheatSheetView())
        sheet.sizingOptions = []
        cheatSheetItem = NSSplitViewItem(inspectorWithViewController: sheet)
        cheatSheetItem.minimumThickness = 290
        cheatSheetItem.maximumThickness = 380
        cheatSheetItem.canCollapse = true
        cheatSheetItem.isCollapsed = !UserDefaults.standard.bool(forKey: Self.cheatSheetKey)

        split.splitViewItems = [libraryItem, editorItem, cheatSheetItem]
        // v2: the divider positions saved before there was a sidebar describe a
        // two-pane window.
        split.splitView.autosaveName = "Doctor.split.v2"
        window?.contentViewController = split

        // The last choice sticks, so a new tab opens the way the previous one was.
        cheatSheetItem.publisher(for: \.isCollapsed)
            .dropFirst()
            .sink { collapsed in
                UserDefaults.standard.set(!collapsed, forKey: Self.cheatSheetKey)
                // The View menu's Show/Hide title reads this through the store.
                DocumentStore.shared.objectWillChange.send()
            }
            .store(in: &observers)

        // Same for the library, and mirror it into the other tabs' windows so
        // switching tabs doesn't flip the sidebar back.
        libraryItem.publisher(for: \.isCollapsed)
            .dropFirst()
            .sink { [weak self] collapsed in
                UserDefaults.standard.set(!collapsed, forKey: Self.libraryKey)
                NotificationCenter.default.post(name: Self.libraryVisibilityChanged, object: self)
                DocumentStore.shared.objectWillChange.send()
            }
            .store(in: &observers)

        NotificationCenter.default.publisher(for: Self.libraryVisibilityChanged)
            .sink { [weak self] _ in
                guard let self else { return }
                let collapsed = !(UserDefaults.standard.object(forKey: Self.libraryKey) as? Bool ?? true)
                if self.libraryItem.isCollapsed != collapsed { self.libraryItem.isCollapsed = collapsed }
            }
            .store(in: &observers)
    }

    var isCheatSheetVisible: Bool { !cheatSheetItem.isCollapsed }
    var isLibraryVisible: Bool { !libraryItem.isCollapsed }

    func toggleLibrary() {
        split.toggleSidebar(nil)
    }

    /// Opens the sidebar if it's hidden, then optionally asks the tree to make
    /// something or to select an item.
    func showLibrary(command: LibraryCommand? = nil, reveal id: UUID? = nil) {
        if libraryItem.isCollapsed { libraryItem.animator().isCollapsed = false }
        window?.makeKeyAndOrderFront(nil)
        MainActor.assumeIsolated {
            if let command { libraryUI.command = command }
            if let id { libraryUI.reveal = id }
        }
    }

    func toggleCheatSheet() {
        split.toggleInspector(nil)
    }

    // MARK: - Title, proxy icon, edited state

    private func observeDocument() {
        markdown.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncWindow() }
            .store(in: &observers)
        syncWindow()
    }

    private func syncWindow() {
        guard let window else { return }
        window.title = markdown.displayName
        window.representedURL = markdown.url
        window.subtitle = markdown.isLibraryBacked
            ? markdown.subtitle
            : (markdown.url.map {
                $0.deletingLastPathComponent().path
                    .replacingOccurrences(of: NSHomeDirectory(), with: "~")
            } ?? "")
        window.isDocumentEdited = markdown.isDirty
        modeGroup?.selectedIndex = EditorMode.allCases.firstIndex(of: markdown.mode) ?? 0
    }

    // MARK: - Window delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        DocumentStore.shared.confirmClose(markdown)
    }

    func windowWillClose(_ notification: Notification) {
        DocumentStore.shared.didClose(self)
    }

    func windowDidBecomeMain(_ notification: Notification) {
        DocumentStore.shared.didActivate(self)
    }

    // MARK: - Responder actions

    /// The native tab bar's + button, and File ▸ New Tab.
    @objc override func newWindowForTab(_ sender: Any?) {
        DocumentStore.shared.newDocument()
    }

    @objc func printDocument(_ sender: Any?) {
        ExportService.printDocument(markdown, in: window)
    }

    @objc private func exportPDF(_ sender: Any?) {
        ExportService.exportPDF(markdown, in: window)
    }

    @objc private func sendToObsidian(_ sender: Any?) {
        ObsidianService.send(markdown)
    }

    @objc private func toggleCheatSheetAction(_ sender: Any?) {
        toggleCheatSheet()
    }

    @objc private func modeChanged(_ sender: NSToolbarItemGroup) {
        guard EditorMode.allCases.indices.contains(sender.selectedIndex) else { return }
        markdown.mode = EditorMode.allCases[sender.selectedIndex]
    }

    // MARK: - Toolbar

    private enum Item {
        static let mode = NSToolbarItem.Identifier("Doctor.mode")
        static let share = NSToolbarItem.Identifier("Doctor.share")
        static let obsidian = NSToolbarItem.Identifier("Doctor.obsidian")
        static let exportPDF = NSToolbarItem.Identifier("Doctor.exportPDF")
        // Our own rather than AppKit's .toggleInspector, which insists on
        // calling itself "Inspector" in its tooltip.
        static let cheatSheet = NSToolbarItem.Identifier("Doctor.cheatSheet")
    }

    private func buildToolbar() {
        // v2: a saved toolbar configuration from before the sidebar would
        // silently leave out the sidebar button.
        let toolbar = NSToolbar(identifier: "Doctor.document.v2")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window?.toolbar = toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var items: [NSToolbarItem.Identifier] = [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, Item.mode, .space]
        if AppSettings.shared.isObsidianConfigured { items.append(Item.obsidian) }
        items += [Item.share, .inspectorTrackingSeparator, .flexibleSpace, Item.cheatSheet]
        return items
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, Item.mode, Item.share, Item.obsidian, Item.exportPDF, .print,
         .inspectorTrackingSeparator, Item.cheatSheet, .space, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case Item.mode:
            let modes = EditorMode.allCases
            let group = NSToolbarItemGroup(
                itemIdentifier: identifier,
                images: modes.map { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: $0.title)! },
                selectionMode: .selectOne,
                labels: modes.map(\.title),
                target: self,
                action: #selector(modeChanged(_:))
            )
            group.label = "View"
            group.paletteLabel = "Preview / Source"
            for (item, shortcut) in zip(group.subitems, ["⌘1", "⌘2"]) {
                item.toolTip = "\(item.label) (\(shortcut))"
            }
            group.selectedIndex = modes.firstIndex(of: markdown.mode) ?? 0
            modeGroup = group
            return group

        case Item.share:
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: identifier)
            item.delegate = self
            item.toolTip = "Share"
            return item

        case Item.obsidian:
            return button(identifier, label: "Send to Obsidian", symbol: "square.stack.3d.up",
                          tip: "Copy into your vault and open it in Obsidian (⇧⌘O)",
                          action: #selector(sendToObsidian(_:)))

        case Item.cheatSheet:
            return button(identifier, label: "Cheat Sheet", symbol: "sidebar.trailing",
                          tip: "Show or hide the Markdown cheat sheet (⌥⌘0)",
                          action: #selector(toggleCheatSheetAction(_:)))

        case Item.exportPDF:
            return button(identifier, label: "Export PDF", symbol: "arrow.down.doc",
                          tip: "Export as PDF (⇧⌘E)", action: #selector(exportPDF(_:)))

        default:
            return nil
        }
    }

    private func button(_ identifier: NSToolbarItem.Identifier, label: String, symbol: String,
                        tip: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = tip
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }
}

extension DocumentWindowController: NSSharingServicePickerToolbarItemDelegate {
    /// A saved file is shared as the file; an untitled one as its text.
    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        if let url = markdown.url { return [url] }
        return markdown.text.isEmpty ? [] : [markdown.text]
    }
}
