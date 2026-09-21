import AppKit

/// Colours and metrics for the editor. Everything is a dynamic `NSColor`, so
/// light and dark are one code path and the appearance switch is instant.
struct MarkdownTheme {
    let settings: AppSettings
    let mode: EditorMode

    init(settings: AppSettings, mode: EditorMode) {
        self.settings = settings
        self.mode = mode
    }

    // MARK: Colours

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        }
    }

    static let text = dynamic(
        light: NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1),
        dark: NSColor(srgbRed: 0.87, green: 0.88, blue: 0.90, alpha: 1)
    )

    static let secondary = dynamic(
        light: NSColor(srgbRed: 0.42, green: 0.45, blue: 0.50, alpha: 1),
        dark: NSColor(srgbRed: 0.58, green: 0.61, blue: 0.66, alpha: 1)
    )

    /// Markdown punctuation when it is visible (source mode, or the active line).
    static let marker = dynamic(
        light: NSColor(srgbRed: 0.62, green: 0.66, blue: 0.72, alpha: 1),
        dark: NSColor(srgbRed: 0.45, green: 0.49, blue: 0.56, alpha: 1)
    )

    static let heading = dynamic(
        light: NSColor(srgbRed: 0.07, green: 0.09, blue: 0.13, alpha: 1),
        dark: NSColor(srgbRed: 0.94, green: 0.95, blue: 0.97, alpha: 1)
    )

    static let accent = dynamic(
        light: NSColor(srgbRed: 0.16, green: 0.40, blue: 0.75, alpha: 1),
        dark: NSColor(srgbRed: 0.47, green: 0.68, blue: 0.98, alpha: 1)
    )

    static let codeText = dynamic(
        light: NSColor(srgbRed: 0.53, green: 0.16, blue: 0.33, alpha: 1),
        dark: NSColor(srgbRed: 0.93, green: 0.62, blue: 0.72, alpha: 1)
    )

    static let codeBackground = dynamic(
        light: NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1),
        dark: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1)
    )

    static let quoteBar = dynamic(
        light: NSColor(srgbRed: 0.80, green: 0.83, blue: 0.87, alpha: 1),
        dark: NSColor(srgbRed: 0.35, green: 0.38, blue: 0.44, alpha: 1)
    )

    static let highlightBackground = dynamic(
        light: NSColor(srgbRed: 1.00, green: 0.93, blue: 0.62, alpha: 1),
        dark: NSColor(srgbRed: 0.45, green: 0.39, blue: 0.13, alpha: 1)
    )

    static let editorBackground = dynamic(
        light: NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        dark: NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1)
    )

    static let chrome = dynamic(
        light: NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1),
        dark: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.19, alpha: 1)
    )

    static let separator = dynamic(
        light: NSColor(srgbRed: 0.87, green: 0.87, blue: 0.89, alpha: 1),
        dark: NSColor(srgbRed: 0.25, green: 0.26, blue: 0.29, alpha: 1)
    )

    static let tagColor = dynamic(
        light: NSColor(srgbRed: 0.35, green: 0.30, blue: 0.68, alpha: 1),
        dark: NSColor(srgbRed: 0.70, green: 0.66, blue: 0.97, alpha: 1)
    )

    // MARK: Fonts

    var baseFont: NSFont {
        mode == .source ? settings.sourceFont : settings.previewBodyFont
    }

    var baseSize: CGFloat {
        mode == .source ? CGFloat(settings.sourceFontSize) : CGFloat(settings.previewFontSize)
    }

    var monospaceFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: baseSize * (mode == .source ? 1.0 : 0.92), weight: .regular)
    }

    /// Heading scale. Source mode keeps a flat rhythm; preview leans into hierarchy.
    func headingFont(level: Int) -> NSFont {
        let scales: [CGFloat] = mode == .source
            ? [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
            : [1.85, 1.50, 1.28, 1.14, 1.04, 1.0]
        let scale = scales[max(0, min(5, level - 1))]
        let size = (baseSize * scale).rounded()
        let weight: NSFont.Weight = level <= 2 ? .bold : .semibold

        if mode == .source {
            let descriptor = settings.sourceFont.fontDescriptor.withSymbolicTraits(.bold)
            return NSFont(descriptor: descriptor, size: size) ?? settings.sourceFont
        }
        if !settings.previewFontName.isEmpty,
           let custom = NSFont(name: settings.previewFontName, size: size) {
            let descriptor = custom.fontDescriptor.withSymbolicTraits(.bold)
            return NSFont(descriptor: descriptor, size: size) ?? custom
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    func applying(traits: NSFontDescriptor.SymbolicTraits, to font: NSFont) -> NSFont {
        let existing = font.fontDescriptor.symbolicTraits
        let descriptor = font.fontDescriptor.withSymbolicTraits(existing.union(traits))
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    // MARK: Metrics

    var lineHeightMultiple: CGFloat { CGFloat(settings.lineSpacing) }

    var paragraphSpacing: CGFloat {
        mode == .source ? 0 : baseSize * 0.55
    }

    /// Width of one indent step for wrapped list lines.
    var listIndentWidth: CGFloat { baseSize * 1.6 }
}
