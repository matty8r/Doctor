import DoctorEditorKit

/// The reader's own minimal settings, conforming to the same protocol
/// `AppSettings` does on macOS — so `MarkdownTheme` and `MarkdownHighlighter`
/// need no iOS-specific branch. There's no font picker, no preferences
/// screen yet; this is exactly what v1 needs and no more. See docs/ios.md.
struct ReaderSettings: MarkdownThemeSettings {
    var previewFontName = ""
    var previewFontSize = 18.0
    var sourceFontSize = 15.0
    var lineSpacing = 1.4
    var hideSyntax = true

    var previewBodyFont: PlatformFont {
        PlatformFont.systemFont(ofSize: previewFontSize)
    }

    var sourceFont: PlatformFont {
        PlatformFont.monospacedSystemFont(ofSize: sourceFontSize, weight: .regular)
    }
}
