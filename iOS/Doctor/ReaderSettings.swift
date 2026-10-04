import DoctorEditorKit

/// The two font choices offered on iOS — deliberately smaller than the Mac
/// app's full font-family picker (`SettingsView.swift`'s `FontPicker`, any
/// installed family). "New York" isn't a nameable font on either platform —
/// `PlatformFont(name: "New York", size:)` returns `nil`, verified against
/// both SDKs directly — so this goes through `Platform.systemFont(design:)`
/// rather than the name-based path `AppSettings` uses.
enum ReaderFont: String, CaseIterable, Identifiable {
    case sans, serif

    var id: String { rawValue }
    var title: String { self == .sans ? "Sans Serif" : "Serif" }
    var design: Platform.FontDesign { self == .sans ? .default : .serif }
}

/// What `MarkdownTheme` reads on iOS. A value type filled in from
/// `ReaderPreferences` each time it's needed, the same role `AppSettings`
/// plays on macOS but without the UserDefaults/menu-bar machinery — that
/// lives in `ReaderPreferences`, the thing that's actually persisted.
struct ReaderSettings: MarkdownThemeSettings {
    var font: ReaderFont = .sans
    var previewFontSize: Double = 18
    var sourceFontSize: Double = 15
    var lineSpacing: Double = 1.4
    var hideSyntax: Bool = true

    /// Always empty: the design-based path below is what carries the font
    /// choice on iOS, not a name `MarkdownTheme` would try to look up.
    var previewFontName: String { "" }
    var previewFontDesign: Platform.FontDesign { font.design }

    var previewBodyFont: PlatformFont {
        Platform.systemFont(ofSize: previewFontSize, weight: .regular, design: font.design)
    }

    var sourceFont: PlatformFont {
        PlatformFont.monospacedSystemFont(ofSize: sourceFontSize, weight: .regular)
    }
}
