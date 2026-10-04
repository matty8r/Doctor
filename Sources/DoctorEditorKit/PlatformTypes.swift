#if canImport(AppKit)
import AppKit

public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
public typealias PlatformFontDescriptor = NSFontDescriptor
public typealias PlatformBezierPath = NSBezierPath
public typealias PlatformFontDescriptorTraits = NSFontDescriptor.SymbolicTraits

#elseif canImport(UIKit)
import UIKit

public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
public typealias PlatformFontDescriptor = UIFontDescriptor
public typealias PlatformBezierPath = UIBezierPath
public typealias PlatformFontDescriptorTraits = UIFontDescriptor.SymbolicTraits
#endif

/// The handful of places AppKit and UIKit disagree on shape rather than just
/// name — collected here so the rendering code itself never branches on
/// platform. Everything else (colors, `NSRange`, `NSAttributedString`,
/// `NSParagraphStyle`, `NSLayoutManager` and friends) is either identical or a
/// straight rename, and is used directly.
public enum Platform {

    /// `NSColor(srgbRed:green:blue:alpha:)` is spelled `UIColor(red:green:blue:alpha:)`
    /// on iOS — UIKit's plain RGB initializer is already sRGB, no prefix needed.
    public static func color(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> PlatformColor {
        #if canImport(AppKit)
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        #elseif canImport(UIKit)
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
        #endif
    }

    /// A color that reads light or dark automatically. AppKit does this with a
    /// dynamic `NSColor`; UIKit's equivalent trait collection API needs the
    /// same closure shape but a different initializer.
    public static func dynamicColor(light: PlatformColor, dark: PlatformColor) -> PlatformColor {
        #if canImport(AppKit)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
        #elseif canImport(UIKit)
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
        #endif
    }

    /// `NSFont(descriptor:size:)` is failable; `UIFont(descriptor:size:)` isn't.
    /// Unified as failable, since that's the weaker of the two guarantees.
    public static func font(descriptor: PlatformFontDescriptor, size: CGFloat) -> PlatformFont? {
        #if canImport(AppKit)
        return NSFont(descriptor: descriptor, size: size)
        #elseif canImport(UIKit)
        return UIFont(descriptor: descriptor, size: size)
        #endif
    }

    /// `NSFontDescriptor.withSymbolicTraits(_:)` never fails; `UIFontDescriptor`'s
    /// can. Falls back to the un-traited descriptor rather than losing the font.
    public static func applying(_ traits: PlatformFontDescriptorTraits, to descriptor: PlatformFontDescriptor) -> PlatformFontDescriptor {
        #if canImport(AppKit)
        return descriptor.withSymbolicTraits(traits)
        #elseif canImport(UIKit)
        return descriptor.withSymbolicTraits(traits) ?? descriptor
        #endif
    }

    /// Bold/italic as a `PlatformFontDescriptorTraits` value. AppKit spells these
    /// `.bold`/`.italic`; UIKit spells the same traits `.traitBold`/`.traitItalic`.
    public static let boldTrait: PlatformFontDescriptorTraits = {
        #if canImport(AppKit)
        return .bold
        #elseif canImport(UIKit)
        return .traitBold
        #endif
    }()

    public static let italicTrait: PlatformFontDescriptorTraits = {
        #if canImport(AppKit)
        return .italic
        #elseif canImport(UIKit)
        return .traitItalic
        #endif
    }()

    /// A platform system-font variant — `default` is San Francisco, `serif` is
    /// New York. Not a nameable font: `NSFont(name: "New York", size:)` and
    /// its `UIFont` equivalent both return `nil` on every OS version checked
    /// (verified against the real SDKs, not assumed) — New York only exists
    /// through this design-aware path, which resolves it to the private
    /// `.NewYork-*` family on both platforms identically.
    public enum FontDesign: String, CaseIterable, Sendable, Codable {
        case `default`, serif

        var title: String {
            switch self {
            case .default: return "Sans Serif"
            case .serif: return "Serif"
            }
        }
    }

    /// The system font in a given design and weight, falling back to the
    /// plain system font on the rare device/OS combination that can't
    /// resolve the descriptor.
    public static func systemFont(ofSize size: CGFloat, weight: PlatformFont.Weight, design: FontDesign) -> PlatformFont {
        let base = PlatformFont.systemFont(ofSize: size, weight: weight)
        guard design != .default else { return base }
        #if canImport(AppKit)
        guard let described = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: described, size: size) ?? base
        #elseif canImport(UIKit)
        guard let described = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: described, size: size)
        #endif
    }

    /// The height a line of this font actually needs — ascender to descender,
    /// available under the same names on both `NSFont` and `UIFont`, unlike
    /// `NSFont.boundingRectForFont`, which iOS doesn't have.
    public static func lineHeight(of font: PlatformFont) -> CGFloat {
        font.ascender - font.descender
    }

    /// A rounded rect as a path, ready to fill or stroke — the one drawing
    /// primitive whose constructor shape actually differs (`xRadius`/`yRadius`
    /// vs. one `cornerRadius`). Every call site here uses an even radius, so a
    /// single value covers both.
    public static func roundedPath(_ rect: CGRect, radius: CGFloat) -> PlatformBezierPath {
        #if canImport(AppKit)
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        #elseif canImport(UIKit)
        return PlatformBezierPath(roundedRect: rect, cornerRadius: radius)
        #endif
    }

    /// The `CGContext` behind the view currently drawing, so a decoration can
    /// save/restore graphics state around a clip. `NSGraphicsContext.current`
    /// on macOS, `UIGraphicsGetCurrentContext()` on iOS — same context either
    /// way, just reached differently.
    public static var currentCGContext: CGContext? {
        #if canImport(AppKit)
        return NSGraphicsContext.current?.cgContext
        #elseif canImport(UIKit)
        return UIGraphicsGetCurrentContext()
        #endif
    }
}
