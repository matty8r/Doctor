import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Owns the open documents, each in its own window. The windows share one tab
/// group, so to the person using it this is still "tabs", but AppKit draws them
/// and only when there's more than one.
final class DocumentStore: ObservableObject {
    static let shared = DocumentStore()

    @Published private(set) var documents: [MarkdownDocument] = []
    /// The document in the main window, which is what menu commands act on.
    @Published private(set) var selectedID: UUID?

    private var controllers: [UUID: DocumentWindowController] = [:]
    private var documentObservers: [UUID: AnyCancellable] = [:]
    private var sessionSaveWork: DispatchWorkItem?
    /// Set once quitting is certain. Windows close as the app goes down, and
    /// that must not be recorded as the person closing their tabs.
    private var isTerminating = false

    private init() {}

    var selected: MarkdownDocument? {
        guard let selectedID else { return nil }
        return documents.first { $0.id == selectedID }
    }

    func controller(for document: MarkdownDocument) -> DocumentWindowController? {
        controllers[document.id]
    }

    var selectedController: DocumentWindowController? {
        selected.flatMap { controllers[$0.id] }
    }

    var hasUnsavedChanges: Bool {
        documents.contains { $0.isDirty }
    }

    // MARK: - Opening

    @discardableResult
    func newDocument(text: String = "") -> MarkdownDocument {
        let doc = MarkdownDocument(text: text)
        insert(doc)
        return doc
    }

    @discardableResult
    func open(url: URL) -> MarkdownDocument? {
        let target = url.standardizedFileURL

        // Already open? Just go to it. Opening a file twice is never what you meant.
        if let existing = documents.first(where: { $0.url?.standardizedFileURL == target }) {
            controllers[existing.id]?.showWindow(nil)
            return existing
        }

        do {
            let doc = try MarkdownDocument(contentsOf: target)
            insert(doc)
            AppSettings.shared.noteRecentFile(target)
            return doc
        } catch {
            presentError(error, title: "Couldn't open \(target.lastPathComponent)")
            return nil
        }
    }

    func open(urls: [URL]) {
        for url in urls { open(url: url) }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = DocumentStore.readableTypes
        panel.allowsOtherFileTypes = true
        panel.message = "Open a Markdown or text file"

        if panel.runModal() == .OK {
            open(urls: panel.urls)
        }
    }

    static var readableTypes: [UTType] {
        var types: [UTType] = [.plainText, .text]
        if let markdown = UTType("net.daringfireball.markdown") {
            types.insert(markdown, at: 0)
        }
        return types
    }

    /// Opens `doc` in a new window, as a tab just after the current one.
    private func insert(_ doc: MarkdownDocument) {
        let controller = DocumentWindowController(markdown: doc)
        controllers[doc.id] = controller
        documents.append(doc)
        observe(doc)

        if let window = controller.window {
            if let current = selectedController?.window, current.isVisible {
                current.addTabbedWindow(window, ordered: .above)
            } else {
                window.center()
            }
        }
        controller.showWindow(nil)
        selectedID = doc.id
        scheduleSessionSave()
    }

    private func observe(_ doc: MarkdownDocument) {
        // Re-publish child changes so tab titles and the status bar stay live.
        documentObservers[doc.id] = doc.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.objectWillChange.send()
                self.scheduleSessionSave()
            }
        }
    }

    // MARK: - Closing

    /// Closes the document's window, asking first if it has unsaved changes.
    /// Returns false if the person cancelled.
    @discardableResult
    func close(_ doc: MarkdownDocument) -> Bool {
        guard confirmClose(doc) else { return false }
        controllers[doc.id]?.window?.close()
        return true
    }

    /// Closes every tab in the front document window, stopping if one is cancelled.
    func closeWindow() {
        guard let window = selectedController?.window else { return }
        for tab in window.tabbedWindows ?? [window] {
            guard let doc = (tab.windowController as? DocumentWindowController)?.markdown,
                  close(doc)
            else { return }
        }
    }

    /// Asks what to do with unsaved changes. True means the window may close.
    func confirmClose(_ doc: MarkdownDocument) -> Bool {
        guard doc.isDirty else { return true }
        switch askAboutUnsavedChanges(doc) {
        case .save: return save(doc)
        case .discard: return true
        case .cancel: return false
        }
    }

    func didClose(_ controller: DocumentWindowController) {
        guard !isTerminating else { return }
        let doc = controller.markdown
        controllers[doc.id] = nil
        documentObservers[doc.id] = nil
        documents.removeAll { $0.id == doc.id }
        if selectedID == doc.id { selectedID = nil }
        scheduleSessionSave()
    }

    func didActivate(_ controller: DocumentWindowController) {
        selectedID = controller.markdown.id
    }

    func prepareToTerminate() {
        persistSession()
        isTerminating = true
    }

    private enum CloseDecision { case save, discard, cancel }

    private func askAboutUnsavedChanges(_ doc: MarkdownDocument) -> CloseDecision {
        let alert = NSAlert()
        alert.messageText = "Save changes to \"\(doc.displayName)\"?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].keyEquivalent = "d"
        alert.buttons[1].keyEquivalentModifierMask = .command
        alert.buttons[2].keyEquivalent = "\u{1b}"

        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }

    // MARK: - Saving

    @discardableResult
    func save(_ doc: MarkdownDocument) -> Bool {
        if doc.url == nil { return saveAs(doc) }
        do {
            try doc.save()
            return true
        } catch {
            presentError(error, title: "Couldn't save \(doc.displayName)")
            return false
        }
    }

    @discardableResult
    func saveAs(_ doc: MarkdownDocument) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = doc.url?.lastPathComponent ?? doc.suggestedFileName
        panel.allowedContentTypes = DocumentStore.readableTypes
        panel.allowsOtherFileTypes = true
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let directory = doc.url?.deletingLastPathComponent() {
            panel.directoryURL = directory
        }

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try doc.save(to: url)
            return true
        } catch {
            presentError(error, title: "Couldn't save \(doc.displayName)")
            return false
        }
    }

    @discardableResult
    func saveSelected() -> Bool {
        guard let doc = selected else { return true }
        return save(doc)
    }

    /// Save every dirty document; returns false if the user cancelled any of them.
    @discardableResult
    func saveAll() -> Bool {
        for doc in documents where doc.isDirty {
            if !save(doc) { return false }
        }
        return true
    }

    // MARK: - Session restore
    //
    // Doctor is meant to be the thing you double-click a file into, so closing
    // and reopening it should feel like nothing happened. Saved files are
    // remembered by path; unsaved buffers are stored whole.

    private struct SessionTab: Codable {
        var path: String?
        var unsavedText: String?
        var mode: String
    }

    private struct Session: Codable {
        var tabs: [SessionTab]
        var selectedIndex: Int
    }

    private var sessionURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = support.appendingPathComponent("Doctor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.json")
    }

    func scheduleSessionSave() {
        sessionSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistSession() }
        sessionSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Documents in the order their tabs appear, window by window.
    private var documentsInTabOrder: [MarkdownDocument] {
        var ordered: [MarkdownDocument] = []
        var seen = Set<UUID>()
        for doc in documents where !seen.contains(doc.id) {
            let group = controllers[doc.id]?.window?.tabbedWindows ?? []
            let tabs = group.compactMap { ($0.windowController as? DocumentWindowController)?.markdown }
            for tab in (tabs.isEmpty ? [doc] : tabs) where seen.insert(tab.id).inserted {
                ordered.append(tab)
            }
        }
        return ordered
    }

    func persistSession() {
        guard let sessionURL, !isTerminating else { return }
        let documents = documentsInTabOrder
        let tabs = documents.map { doc -> SessionTab in
            SessionTab(
                path: doc.url?.path,
                // Only carry text we'd otherwise lose.
                unsavedText: (doc.url == nil || doc.isDirty) ? doc.text : nil,
                mode: doc.mode.rawValue
            )
        }
        let selectedIndex = documents.firstIndex { $0.id == selectedID } ?? 0
        let session = Session(tabs: tabs, selectedIndex: selectedIndex)
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: sessionURL, options: .atomic)
        }
    }

    func restoreSession() {
        guard documents.isEmpty,
              let sessionURL,
              let data = try? Data(contentsOf: sessionURL),
              let session = try? JSONDecoder().decode(Session.self, from: data)
        else { return }

        for tab in session.tabs {
            let mode = EditorMode(rawValue: tab.mode)
            if let path = tab.path {
                let url = URL(fileURLWithPath: path)
                if let unsaved = tab.unsavedText {
                    // The buffer was dirty at quit: restore the edit, not the file.
                    let doc = MarkdownDocument(text: unsaved, url: nil, mode: mode)
                    if FileManager.default.fileExists(atPath: path), let opened = open(url: url) {
                        opened.text = unsaved
                        opened.mode = mode ?? opened.mode
                    } else {
                        insert(doc)
                    }
                } else if FileManager.default.fileExists(atPath: path) {
                    let opened = open(url: url)
                    opened?.mode = mode ?? AppSettings.shared.defaultMode
                }
            } else if let unsaved = tab.unsavedText, !unsaved.isEmpty {
                insert(MarkdownDocument(text: unsaved, url: nil, mode: mode))
            }
        }

        if documents.indices.contains(session.selectedIndex) {
            controllers[documents[session.selectedIndex].id]?.showWindow(nil)
        }
    }

    // MARK: - Errors

    func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func presentMessage(_ message: String, detail: String = "") {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
