import AppKit
import Foundation
import Observation

import DoctorEditorKit
/// One open tab: a Markdown file (or an untitled buffer) plus its editing state.
final class MarkdownDocument: ObservableObject, Identifiable {
    let id = UUID()

    @Published var text: String {
        didSet {
            isDirty = (text != savedText)
            if isDirty, libraryItem != nil { scheduleAutosave() }
        }
    }

    @Published private(set) var url: URL?
    @Published private(set) var isDirty: Bool = false
    @Published var mode: EditorMode

    /// The synced library document this tab edits, when it's one — otherwise
    /// the tab is a file on disk (`url`) or an unsaved buffer. A library tab has
    /// no `url`; it saves itself into the library as you type, the way Notes
    /// does, and picks up edits made on another device.
    private(set) var libraryItem: LibraryDocument?
    var isLibraryBacked: Bool { libraryItem != nil }
    private var autosaveWork: DispatchWorkItem?

    /// Set when the file changes underneath us while the buffer is dirty, so the
    /// UI can offer a choice instead of silently picking a winner.
    @Published var hasExternalChanges: Bool = false

    /// Scroll offset, remembered so switching tabs doesn't lose your place.
    var scrollOffset: CGFloat = 0
    var selectedRange: NSRange = NSRange(location: 0, length: 0)

    private var savedText: String
    private var encoding: String.Encoding = .utf8
    private var watcher: FileWatcher?
    /// Our own saves fire the file watcher; ignore events for a moment afterwards.
    private var ignoreWatchUntil: Date = .distantPast

    init(text: String = "", url: URL? = nil, mode: EditorMode? = nil) {
        self.text = text
        self.savedText = text
        self.url = url
        self.mode = mode ?? AppSettings.shared.defaultMode
        self.isDirty = false
        startWatching()
    }

    /// A tab on a document in the synced library.
    convenience init(library item: LibraryDocument, mode: EditorMode? = nil) {
        self.init(text: item.body, url: nil, mode: mode)
        self.libraryItem = item
        observeLibraryItem()
    }

    convenience init(contentsOf url: URL) throws {
        var usedEncoding: String.Encoding = .utf8
        let contents: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            contents = utf8
        } else {
            // Fall back to whatever the system can detect (Latin-1, UTF-16, …).
            contents = try String(contentsOf: url, usedEncoding: &usedEncoding)
        }
        self.init(text: contents, url: url)
        self.encoding = usedEncoding
    }

    var displayName: String {
        if let libraryItem {
            if !libraryItem.title.isEmpty { return libraryItem.title }
            return firstHeading ?? "Untitled"
        }
        if let url { return url.lastPathComponent }
        if let heading = firstHeading, !heading.isEmpty { return heading }
        return "Untitled"
    }

    var subtitle: String {
        if let libraryItem {
            return MainActor.assumeIsolated { LibraryStore.shared.path(of: libraryItem) }
        }
        guard let url else { return "Not saved" }
        return url.deletingLastPathComponent().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// First ATX heading, used to name untitled documents on save and in tabs.
    var firstHeading: String? {
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(40) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#") else { continue }
            let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return title }
        }
        return nil
    }

    // MARK: - Statistics

    var wordCount: Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .localized]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    var characterCount: Int { text.count }

    var lineCount: Int {
        text.isEmpty ? 1 : text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    /// Rough reading time, the way a reader actually cares about it.
    var readingMinutes: Int { max(1, Int((Double(wordCount) / 225.0).rounded(.up))) }

    // MARK: - Loading and saving

    func save() throws {
        if libraryItem != nil { saveToLibrary(); return }
        guard let url else { throw DocumentError.noLocation }
        try write(to: url)
    }

    /// Writes a copy to disk without changing what this tab *is* — a library
    /// document stays a library document. This is "Save As…" for a synced tab.
    func exportCopy(to url: URL) throws {
        try encodedData().write(to: url, options: .atomic)
        AppSettings.shared.noteRecentFile(url)
    }

    func save(to url: URL) throws {
        try write(to: url)
        self.url = url
        AppSettings.shared.noteRecentFile(url)
        startWatching()
    }

    private func encodedData() throws -> Data {
        var body = text
        // Files should end with a newline; tools downstream assume it.
        if !body.isEmpty && !body.hasSuffix("\n") { body.append("\n") }

        guard let data = body.data(using: encoding) ?? body.data(using: .utf8) else {
            throw DocumentError.encodingFailed
        }
        return data
    }

    private func write(to url: URL) throws {
        let data = try encodedData()

        ignoreWatchUntil = Date().addingTimeInterval(1.0)
        try data.write(to: url, options: .atomic)

        savedText = text
        isDirty = false
        hasExternalChanges = false
    }

    /// Re-read from disk (or from the library), discarding unsaved changes.
    func revert() throws {
        if let libraryItem {
            autosaveWork?.cancel()
            savedText = libraryItem.body
            text = libraryItem.body
            isDirty = false
            hasExternalChanges = false
            return
        }
        guard let url else { throw DocumentError.noLocation }
        let contents = try String(contentsOf: url, encoding: encoding)
        text = contents
        savedText = contents
        isDirty = false
        hasExternalChanges = false
    }

    /// A filename to propose when this document has never been saved.
    var suggestedFileName: String {
        let named = libraryItem.flatMap { $0.title.isEmpty ? nil : $0.title } ?? firstHeading
        let base = named.map(MarkdownDocument.sanitizeFileName) ?? "Untitled"
        return base.isEmpty ? "Untitled.md" : "\(base).md"
    }

    static func sanitizeFileName(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = raw.components(separatedBy: illegal).joined(separator: " ")
        let collapsed = cleaned.split(separator: " ").joined(separator: " ")
        return String(collapsed.prefix(80)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Library backing

    private func scheduleAutosave() {
        autosaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveToLibrary() }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// Writes the buffer into the library document. SwiftData persists it and,
    /// when the store is cloud-backed, CloudKit carries it to the other devices.
    private func saveToLibrary() {
        guard let item = libraryItem else { return }
        autosaveWork?.cancel()
        MainActor.assumeIsolated {
            item.body = text
            // Only name an untitled document; never overwrite a title someone
            // typed (on the phone, say) with whatever the first heading is.
            if item.title.isEmpty, let heading = firstHeading { item.title = heading }
            item.touch()
            LibraryStore.shared.save()
        }
        savedText = text
        isDirty = false
        hasExternalChanges = false
    }

    /// Flushes a pending autosave now — on close and on quit.
    func flushToLibrary() {
        if libraryItem != nil, isDirty { saveToLibrary() }
    }

    /// SwiftData models are observable, so a body that arrives from CloudKit
    /// (or an edit from another window) wakes this; re-arm after each change.
    private func observeLibraryItem() {
        guard let item = libraryItem else { return }
        withObservationTracking {
            _ = item.body
            _ = item.title
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.libraryItemChanged()
                self?.observeLibraryItem()
            }
        }
    }

    private func libraryItemChanged() {
        guard let item = libraryItem else { return }

        // Deleted elsewhere (the phone, the library window): keep the text as
        // an unsaved buffer rather than losing it with the record.
        if item.modelContext == nil {
            autosaveWork?.cancel()
            libraryItem = nil
            savedText = ""
            isDirty = true
            objectWillChange.send()
            return
        }

        objectWillChange.send() // the title may have changed
        let body = item.body
        guard body != savedText else { return }
        if isDirty {
            hasExternalChanges = true
        } else {
            savedText = body
            text = body
            isDirty = false
        }
    }

    // MARK: - External change detection

    private func startWatching() {
        watcher = nil
        guard let url else { return }
        watcher = FileWatcher(url: url) { [weak self] in
            DispatchQueue.main.async { self?.handleExternalChange() }
        }
    }

    private func handleExternalChange() {
        guard let url, Date() > ignoreWatchUntil else { return }
        guard let contents = try? String(contentsOf: url, encoding: encoding) else { return }
        guard contents != savedText else { return }

        if isDirty {
            // Don't destroy unsaved work; let the user decide.
            hasExternalChanges = true
        } else {
            text = contents
            savedText = contents
            isDirty = false
        }
    }

    func acceptExternalChanges() {
        try? revert()
    }

    func dismissExternalChanges() {
        hasExternalChanges = false
        // Keep the in-memory version; the next save wins.
        savedText = ""
        isDirty = true
    }
}

enum DocumentError: LocalizedError {
    case noLocation
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noLocation: return "This document hasn't been saved anywhere yet."
        case .encodingFailed: return "The document couldn't be encoded for writing."
        }
    }
}
