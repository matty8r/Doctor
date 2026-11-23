import Foundation
/// Colours and metrics for the editor. Everything is a dynamic `PlatformColor`,
/// so light and dark are one code path and the appearance switch is instant.
public struct MarkdownTheme {
    let settings: any MarkdownThemeSettings
    let mode: EditorMode

    public init(settings: any MarkdownThemeSettings, mode: EditorMode) {
        self.settings = settings
        self.mode = mode
    }

    // MARK: Colours

    public static let text = Platform.dynamicColor(
        light: Platform.color(red: 0.11, green: 0.12, blue: 0.14, alpha: 1),
        dark: Platform.color(red: 0.87, green: 0.88, blue: 0.90, alpha: 1)
    )

    public static let secondary = Platform.dynamicColor(
        light: Platform.color(red: 0.42, green: 0.45, blue: 0.50, alpha: 1),
        dark: Platform.color(red: 0.58, green: 0.61, blue: 0.66, alpha: 1)
    )

    /// Markdown punctuation when it is visible (source mode, or the active line).
    public static let marker = Platform.dynamicColor(
        light: Platform.color(red: 0.62, green: 0.66, blue: 0.72, alpha: 1),
        dark: Platform.color(red: 0.45, green: 0.49, blue: 0.56, alpha: 1)
    )

    public static let heading = Platform.dynamicColor(
        light: Platform.color(red: 0.07, green: 0.09, blue: 0.13, alpha: 1),
        dark: Platform.color(red: 0.94, green: 0.95, blue: 0.97, alpha: 1)
    )

    public static let accent = Platform.dynamicColor(
        light: Platform.color(red: 0.16, green: 0.40, blue: 0.75, alpha: 1),
        dark: Platform.color(red: 0.47, green: 0.68, blue: 0.98, alpha: 1)
    )

    /// Folders in the library: the icon's own ink and paper — black by day,
    /// white by night — so they follow the monochrome identity of the app
    /// rather than the system's blue (which is also Doctor's link colour).
    public static let folderTint = Platform.dynamicColor(
        light: Platform.color(red: 0.063, green: 0.067, blue: 0.078, alpha: 1),  // #101114, the icon's ink
        dark: Platform.color(red: 0.973, green: 0.969, blue: 0.953, alpha: 1)    // #F8F7F3, the icon's paper
    )

    public static let codeText = Platform.dynamicColor(
        light: Platform.color(red: 0.53, green: 0.16, blue: 0.33, alpha: 1),
        dark: Platform.color(red: 0.93, green: 0.62, blue: 0.72, alpha: 1)
    )

    public static let codeBackground = Platform.dynamicColor(
        light: Platform.color(red: 0.96, green: 0.96, blue: 0.97, alpha: 1),
        dark: Platform.color(red: 0.16, green: 0.17, blue: 0.20, alpha: 1)
    )

    public static let quoteBar = Platform.dynamicColor(
        light: Platform.color(red: 0.80, green: 0.83, blue: 0.87, alpha: 1),
        dark: Platform.color(red: 0.35, green: 0.38, blue: 0.44, alpha: 1)
    )

    public static let highlightBackground = Platform.dynamicColor(
        light: Platform.color(red: 1.00, green: 0.93, blue: 0.62, alpha: 1),
        dark: Platform.color(red: 0.45, green: 0.39, blue: 0.13, alpha: 1)
    )

    public static let editorBackground = Platform.dynamicColor(
        light: Platform.color(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        dark: Platform.color(red: 0.12, green: 0.13, blue: 0.15, alpha: 1)
    )

    public static let chrome = Platform.dynamicColor(
        light: Platform.color(red: 0.95, green: 0.95, blue: 0.96, alpha: 1),
        dark: Platform.color(red: 0.16, green: 0.17, blue: 0.19, alpha: 1)
    )

    public static let separator = Platform.dynamicColor(
        light: Platform.color(red: 0.87, green: 0.87, blue: 0.89, alpha: 1),
        dark: Platform.color(red: 0.25, green: 0.26, blue: 0.29, alpha: 1)
    )

    public static let tagColor = Platform.dynamicColor(
        light: Platform.color(red: 0.35, green: 0.30, blue: 0.68, alpha: 1),
        dark: Platform.color(red: 0.70, green: 0.66, blue: 0.97, alpha: 1)
    )

    // MARK: Fonts

    public var baseFont: PlatformFont {
        mode == .source ? settings.sourceFont : settings.previewBodyFont
    }

    public var baseSize: CGFloat {
        mode == .source ? CGFloat(settings.sourceFontSize) : CGFloat(settings.previewFontSize)
    }

    public var monospaceFont: PlatformFont {
        PlatformFont.monospacedSystemFont(ofSize: baseSize * (mode == .source ? 1.0 : 0.92), weight: .regular)
    }

    /// Heading scale. Source mode keeps a flat rhythm; preview leans into hierarchy.
    public func headingFont(level: Int) -> PlatformFont {
        let scales: [CGFloat] = mode == .source
            ? [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
            : [1.85, 1.50, 1.28, 1.14, 1.04, 1.0]
        let scale = scales[max(0, min(5, level - 1))]
        let size = (baseSize * scale).rounded()
        let weight: PlatformFont.Weight = level <= 2 ? .bold : .semibold

        if mode == .source {
            let descriptor = Platform.applying(Platform.boldTrait, to: settings.sourceFont.fontDescriptor)
            return Platform.font(descriptor: descriptor, size: size) ?? settings.sourceFont
        }
        if !settings.previewFontName.isEmpty,
           let custom = PlatformFont(name: settings.previewFontName, size: size) {
            let descriptor = Platform.applying(Platform.boldTrait, to: custom.fontDescriptor)
            return Platform.font(descriptor: descriptor, size: size) ?? custom
        }
        return Platform.systemFont(ofSize: size, weight: weight, design: settings.previewFontDesign)
    }

    public func applying(traits: PlatformFontDescriptorTraits, to font: PlatformFont) -> PlatformFont {
        let existing = font.fontDescriptor.symbolicTraits
        let descriptor = Platform.applying(existing.union(traits), to: font.fontDescriptor)
        return Platform.font(descriptor: descriptor, size: font.pointSize) ?? font
    }

    // MARK: Metrics

    public var lineHeightMultiple: CGFloat { CGFloat(settings.lineSpacing) }

    public var paragraphSpacing: CGFloat {
        mode == .source ? 0 : baseSize * 0.55
    }

    /// Width of one indent step for wrapped list lines.
    public var listIndentWidth: CGFloat { baseSize * 1.6 }
}
