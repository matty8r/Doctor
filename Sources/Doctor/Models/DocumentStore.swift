import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Owns the open tabs. There is exactly one window, so there is exactly one store.
final class DocumentStore: ObservableObject {
    static let shared = DocumentStore()

    @Published private(set) var documents: [MarkdownDocument] = []
    @Published var selectedID: UUID?

    private var documentObservers: [UUID: AnyCancellable] = [:]
    private var sessionSaveWork: DispatchWorkItem?

    private init() {}

    var selected: MarkdownDocument? {
        guard let selectedID else { return documents.first }
        return documents.first { $0.id == selectedID } ?? documents.first
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
            selectedID = existing.id
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

    private func insert(_ doc: MarkdownDocument) {
        let insertionIndex: Int
        if let selectedID, let current = documents.firstIndex(where: { $0.id == selectedID }) {
            insertionIndex = current + 1
        } else {
            insertionIndex = documents.count
        }
        documents.insert(doc, at: insertionIndex)
        selectedID = doc.id
        observe(doc)
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

    /// Returns false if the user cancelled.
    @discardableResult
    func close(_ doc: MarkdownDocument) -> Bool {
        if doc.isDirty {
            switch confirmClose(doc) {
            case .save:
                guard save(doc) else { return false }
            case .discard:
                break
            case .cancel:
                return false
            }
        }
        remove(doc)
        return true
    }

    @discardableResult
    func closeSelected() -> Bool {
        guard let doc = selected else { return true }
        return close(doc)
    }

    private func remove(_ doc: MarkdownDocument) {
        guard let index = documents.firstIndex(where: { $0.id == doc.id }) else { return }
        documentObservers[doc.id] = nil
        documents.remove(at: index)
        if selectedID == doc.id {
            let next = min(index, documents.count - 1)
            selectedID = next >= 0 ? documents[next].id : nil
        }
        scheduleSessionSave()
    }

    private enum CloseDecision { case save, discard, cancel }

    private func confirmClose(_ doc: MarkdownDocument) -> CloseDecision {
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

    // MARK: - Tab navigation

    func selectNextTab() { cycleTab(by: 1) }
    func selectPreviousTab() { cycleTab(by: -1) }

    private func cycleTab(by delta: Int) {
        guard documents.count > 1,
              let current = documents.firstIndex(where: { $0.id == selectedID })
        else { return }
        let next = (current + delta + documents.count) % documents.count
        selectedID = documents[next].id
    }

    func selectTab(at index: Int) {
        guard documents.indices.contains(index) else { return }
        selectedID = documents[index].id
    }

    func moveTab(from source: Int, to destination: Int) {
        guard documents.indices.contains(source),
              destination >= 0, destination <= documents.count,
              source != destination
        else { return }
        let doc = documents.remove(at: source)
        documents.insert(doc, at: destination > source ? destination - 1 : destination)
        scheduleSessionSave()
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

    func persistSession() {
        guard let sessionURL else { return }
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
            selectedID = documents[session.selectedIndex].id
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
