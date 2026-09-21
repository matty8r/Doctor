import AppKit

/// Files a document into an Obsidian vault and opens it there.
///
/// This copies rather than links: the vault gets a real file, the original stays
/// where it was, and nothing depends on Doctor still being around afterwards.
enum ObsidianService {

    enum ObsidianError: LocalizedError {
        case notConfigured
        case vaultMissing(String)
        case emptyDocument

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "No Obsidian vault is set up yet."
            case .vaultMissing(let path):
                return "The vault folder no longer exists at \(path)."
            case .emptyDocument:
                return "There's nothing in this document to send."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .notConfigured, .vaultMissing:
                return "Choose your vault folder in Doctor ▸ Settings ▸ Obsidian."
            case .emptyDocument:
                return nil
            }
        }
    }

    @discardableResult
    static func send(_ document: MarkdownDocument, settings: AppSettings = .shared) -> Bool {
        do {
            let destination = try file(document, settings: settings)
            if settings.revealAfterSend {
                open(destination.relativePath, vault: settings.effectiveVaultName)
            }
            return true
        } catch {
            presentFailure(error)
            return false
        }
    }

    /// Writes the document into the vault and returns where it landed.
    private static func file(
        _ document: MarkdownDocument,
        settings: AppSettings
    ) throws -> (url: URL, relativePath: String) {
        guard settings.isObsidianConfigured else { throw ObsidianError.notConfigured }
        guard !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ObsidianError.emptyDocument
        }

        let vault = URL(fileURLWithPath: settings.vaultPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: vault.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw ObsidianError.vaultMissing(vault.path) }

        var folder = vault
        let subfolder = settings.vaultFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if !subfolder.isEmpty {
            folder = vault.appendingPathComponent(subfolder, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let name = uniqueName(
            base: document.url?.deletingPathExtension().lastPathComponent
                ?? ExportService.baseName(for: document),
            in: folder
        )
        let destination = folder.appendingPathComponent(name)

        var body = document.text
        if !body.hasSuffix("\n") { body.append("\n") }
        try body.write(to: destination, atomically: true, encoding: .utf8)

        var relative = name
        if !subfolder.isEmpty { relative = subfolder + "/" + name }
        return (destination, relative)
    }

    /// Obsidian refuses to overwrite silently, and so do we.
    private static func uniqueName(base: String, in folder: URL) -> String {
        let cleaned = MarkdownDocument.sanitizeFileName(base.isEmpty ? "Untitled" : base)
        var candidate = cleaned + ".md"
        var counter = 2

        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            candidate = "\(cleaned) \(counter).md"
            counter += 1
        }
        return candidate
    }

    private static func open(_ relativePath: String, vault: String) {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "vault", value: vault),
            URLQueryItem(name: "file", value: relativePath)
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    private static func presentFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = error.localizedDescription
        if let suggestion = (error as? ObsidianError)?.recoverySuggestion {
            alert.informativeText = suggestion
        } else if let underlying = (error as NSError).localizedRecoverySuggestion {
            alert.informativeText = underlying
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        if case ObsidianError.notConfigured = error {
            alert.addButton(withTitle: "Open Settings…")
            if alert.runModal() == .alertSecondButtonReturn {
                SettingsWindow.show()
            }
            return
        }
        alert.runModal()
    }
}
