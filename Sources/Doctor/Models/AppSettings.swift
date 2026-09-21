import AppKit
import SwiftUI

/// How the editor displays the document. There are only two, on purpose:
/// live preview *is* the reading experience, it just happens to be editable.
enum EditorMode: String, CaseIterable, Identifiable, Codable {
    case preview
    case source

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preview: return "Preview"
        case .source: return "Source"
        }
    }

    var symbol: String {
        switch self {
        case .preview: return "doc.richtext"
        case .source: return "chevron.left.forwardslash.chevron.right"
        }
    }

    var toggled: EditorMode { self == .preview ? .source : .preview }
}

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// User preferences, backed by `UserDefaults` and published so SwiftUI and the
/// AppKit editor both react to changes.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let theme = "theme"
        static let defaultMode = "defaultMode"
        static let previewFontName = "previewFontName"
        static let previewFontSize = "previewFontSize"
        static let sourceFontName = "sourceFontName"
        static let sourceFontSize = "sourceFontSize"
        static let lineSpacing = "lineSpacing"
        static let contentWidth = "contentWidth"
        static let hideSyntax = "hideSyntax"
        static let continuousSpellCheck = "continuousSpellCheck"
        static let smartLists = "smartLists"
        static let vaultPath = "obsidianVaultPath"
        static let vaultName = "obsidianVaultName"
        static let vaultFolder = "obsidianVaultFolder"
        static let revealAfterSend = "obsidianRevealAfterSend"
        static let recentFiles = "recentFiles"
    }

    private let defaults = UserDefaults.standard

    @Published var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Key.theme)
            applyAppearance()
        }
    }

    @Published var defaultMode: EditorMode {
        didSet { defaults.set(defaultMode.rawValue, forKey: Key.defaultMode) }
    }

    @Published var previewFontName: String {
        didSet { defaults.set(previewFontName, forKey: Key.previewFontName) }
    }

    @Published var previewFontSize: Double {
        didSet { defaults.set(previewFontSize, forKey: Key.previewFontSize) }
    }

    @Published var sourceFontName: String {
        didSet { defaults.set(sourceFontName, forKey: Key.sourceFontName) }
    }

    @Published var sourceFontSize: Double {
        didSet { defaults.set(sourceFontSize, forKey: Key.sourceFontSize) }
    }

    @Published var lineSpacing: Double {
        didSet { defaults.set(lineSpacing, forKey: Key.lineSpacing) }
    }

    /// Maximum width of the text column in preview mode. Long measures are hard
    /// to read; this keeps prose around 70–80 characters regardless of window size.
    @Published var contentWidth: Double {
        didSet { defaults.set(contentWidth, forKey: Key.contentWidth) }
    }

    /// Hide Markdown punctuation on lines the cursor is not on.
    @Published var hideSyntax: Bool {
        didSet { defaults.set(hideSyntax, forKey: Key.hideSyntax) }
    }

    @Published var continuousSpellCheck: Bool {
        didSet { defaults.set(continuousSpellCheck, forKey: Key.continuousSpellCheck) }
    }

    /// Continue lists and blockquotes when you press Return.
    @Published var smartLists: Bool {
        didSet { defaults.set(smartLists, forKey: Key.smartLists) }
    }

    @Published var vaultPath: String {
        didSet { defaults.set(vaultPath, forKey: Key.vaultPath) }
    }

    /// Obsidian identifies vaults by name in its URL scheme. Empty means
    /// "use the vault folder's own name", which is right almost always.
    @Published var vaultName: String {
        didSet { defaults.set(vaultName, forKey: Key.vaultName) }
    }

    /// Subfolder inside the vault that Doctor files land in, e.g. "Inbox".
    @Published var vaultFolder: String {
        didSet { defaults.set(vaultFolder, forKey: Key.vaultFolder) }
    }

    @Published var revealAfterSend: Bool {
        didSet { defaults.set(revealAfterSend, forKey: Key.revealAfterSend) }
    }

    @Published private(set) var recentFiles: [URL]

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Key.theme: AppTheme.system.rawValue,
            Key.defaultMode: EditorMode.preview.rawValue,
            Key.previewFontName: "",
            Key.previewFontSize: 16.0,
            Key.sourceFontName: "",
            Key.sourceFontSize: 13.5,
            Key.lineSpacing: 1.35,
            Key.contentWidth: 760.0,
            Key.hideSyntax: true,
            Key.continuousSpellCheck: true,
            Key.smartLists: true,
            Key.vaultPath: "",
            Key.vaultName: "",
            Key.vaultFolder: "",
            Key.revealAfterSend: true
        ])

        theme = AppTheme(rawValue: d.string(forKey: Key.theme) ?? "") ?? .system
        defaultMode = EditorMode(rawValue: d.string(forKey: Key.defaultMode) ?? "") ?? .preview
        previewFontName = d.string(forKey: Key.previewFontName) ?? ""
        previewFontSize = d.double(forKey: Key.previewFontSize)
        sourceFontName = d.string(forKey: Key.sourceFontName) ?? ""
        sourceFontSize = d.double(forKey: Key.sourceFontSize)
        lineSpacing = d.double(forKey: Key.lineSpacing)
        contentWidth = d.double(forKey: Key.contentWidth)
        hideSyntax = d.bool(forKey: Key.hideSyntax)
        continuousSpellCheck = d.bool(forKey: Key.continuousSpellCheck)
        smartLists = d.bool(forKey: Key.smartLists)
        vaultPath = d.string(forKey: Key.vaultPath) ?? ""
        vaultName = d.string(forKey: Key.vaultName) ?? ""
        vaultFolder = d.string(forKey: Key.vaultFolder) ?? ""
        revealAfterSend = d.bool(forKey: Key.revealAfterSend)
        recentFiles = (d.array(forKey: Key.recentFiles) as? [String] ?? [])
            .map { URL(fileURLWithPath: $0) }
    }

    func applyAppearance() {
        NSApp?.appearance = theme.appearance
    }

    // MARK: Fonts

    var previewBodyFont: NSFont {
        if !previewFontName.isEmpty, let font = NSFont(name: previewFontName, size: previewFontSize) {
            return font
        }
        return NSFont.systemFont(ofSize: previewFontSize)
    }

    var sourceFont: NSFont {
        if !sourceFontName.isEmpty, let font = NSFont(name: sourceFontName, size: sourceFontSize) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: sourceFontSize, weight: .regular)
    }

    var monospaceFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: previewFontSize * 0.92, weight: .regular)
    }

    // MARK: Recent files

    func noteRecentFile(_ url: URL) {
        var list = recentFiles.filter { $0.standardizedFileURL != url.standardizedFileURL }
        list.insert(url.standardizedFileURL, at: 0)
        if list.count > 12 { list = Array(list.prefix(12)) }
        recentFiles = list
        defaults.set(list.map(\.path), forKey: Key.recentFiles)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func clearRecentFiles() {
        recentFiles = []
        defaults.set([String](), forKey: Key.recentFiles)
    }

    /// The vault name Obsidian expects, falling back to the folder name.
    var effectiveVaultName: String {
        if !vaultName.isEmpty { return vaultName }
        guard !vaultPath.isEmpty else { return "" }
        return URL(fileURLWithPath: vaultPath).lastPathComponent
    }

    var isObsidianConfigured: Bool {
        !vaultPath.isEmpty && !effectiveVaultName.isEmpty
    }
}
