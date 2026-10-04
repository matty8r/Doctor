/// The handful of preferences `MarkdownTheme` actually reads. macOS's
/// `AppSettings` conforms to this directly — it already has every property,
/// backed by `UserDefaults` and a menu bar. iOS's reader has no menu bar and no
/// per-document font picker yet, so it can satisfy this with a plain struct of
/// fixed values and gain real preferences later without touching the renderer.
public protocol MarkdownThemeSettings {
    var sourceFont: PlatformFont { get }
    var previewBodyFont: PlatformFont { get }
    var previewFontName: String { get }
    var previewFontSize: Double { get }
    var sourceFontSize: Double { get }
    var lineSpacing: Double { get }
    var hideSyntax: Bool { get }
    /// Used only for headings' own font construction (`MarkdownTheme.
    /// headingFont`), which doesn't go through `previewBodyFont` — everything
    /// else that wants a serif body already gets it by implementing
    /// `previewBodyFont` accordingly. Defaults to `.default` (no change in
    /// behavior) so existing conformers — `AppSettings` on macOS — need no
    /// changes at all.
    var previewFontDesign: Platform.FontDesign { get }
}

extension MarkdownThemeSettings {
    public var previewFontDesign: Platform.FontDesign { .default }
}

/// A fixed set of reasonable values — what the iOS reader uses today, and
/// what any platform can pass in a pinch.
public struct DefaultThemeSettings: MarkdownThemeSettings {
    public var previewFontName: String
    public var previewFontSize: Double
    public var sourceFontSize: Double
    public var lineSpacing: Double
    public var hideSyntax: Bool

    public init(
        previewFontName: String = "",
        previewFontSize: Double = 17,
        sourceFontSize: Double = 15,
        lineSpacing: Double = 1.35,
        hideSyntax: Bool = true
    ) {
        self.previewFontName = previewFontName
        self.previewFontSize = previewFontSize
        self.sourceFontSize = sourceFontSize
        self.lineSpacing = lineSpacing
        self.hideSyntax = hideSyntax
    }

    public var previewBodyFont: PlatformFont {
        if !previewFontName.isEmpty, let font = PlatformFont(name: previewFontName, size: previewFontSize) {
            return font
        }
        return PlatformFont.systemFont(ofSize: previewFontSize)
    }

    public var sourceFont: PlatformFont {
        PlatformFont.monospacedSystemFont(ofSize: sourceFontSize, weight: .regular)
    }
}
