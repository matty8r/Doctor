#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// The engine behind preview mode.
///
/// Two jobs, both at the glyph layer so the underlying text is never altered:
///
/// 1. **Concealment.** Markdown punctuation on lines you aren't editing is given
///    the `.null` glyph property, which removes it from layout entirely — the
///    characters are still in the document, still saved, still there when the
///    caret arrives, but they take up no space and draw nothing.
/// 2. **Decoration.** Code blocks, blockquote bars and horizontal rules are
///    drawn behind the text, because punctuation alone can't make a code block
///    look like a code block.
///
/// Cross-platform: on iOS, host it in a `UITextView` built the same manual way
/// as on macOS — `UITextView(frame:textContainer:)` with this as the layout
/// manager — rather than the default TextKit 2 stack.
public final class ConcealingLayoutManager: NSLayoutManager {

    public override init() {
        super.init()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Sorted, non-overlapping ranges whose glyphs should vanish.
    public private(set) var concealedRanges: [NSRange] = []
    public private(set) var decorations: [BlockDecoration] = []

    // MARK: - State

    /// Callers redraw the view themselves after this returns — unlike AppKit,
    /// UIKit's `NSLayoutManager` has no reliable "my text view" back-reference
    /// to reach for them.
    public func update(concealed: [NSRange], decorations: [BlockDecoration]) {
        let dirty = boundsOfDifference(between: concealedRanges, and: concealed)
        concealedRanges = concealed
        self.decorations = decorations

        // Moving the caret changes concealment on at most two lines, so only
        // re-lay-out the span that actually differs. Invalidating the whole
        // document on every arrow key makes long files crawl.
        if let dirty, let length = textStorage?.length, length > 0 {
            let clamped = NSRange(
                location: min(dirty.location, length),
                length: min(dirty.length, max(0, length - min(dirty.location, length)))
            )
            invalidateGlyphs(forCharacterRange: clamped, changeInLength: 0, actualCharacterRange: nil)
            invalidateLayout(forCharacterRange: clamped, actualCharacterRange: nil)
        }
    }

    /// The span covering every range that appears in one list but not the other.
    private func boundsOfDifference(between old: [NSRange], and new: [NSRange]) -> NSRange? {
        if old.isEmpty && new.isEmpty { return nil }

        var lower = Int.max
        var upper = Int.min

        func include(_ range: NSRange) {
            lower = min(lower, range.location)
            upper = max(upper, NSMaxRange(range))
        }

        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            if oldIndex >= old.count { include(new[newIndex]); newIndex += 1; continue }
            if newIndex >= new.count { include(old[oldIndex]); oldIndex += 1; continue }

            let a = old[oldIndex]
            let b = new[newIndex]
            if a.location == b.location && a.length == b.length {
                oldIndex += 1
                newIndex += 1
            } else if a.location <= b.location {
                include(a)
                oldIndex += 1
            } else {
                include(b)
                newIndex += 1
            }
        }

        guard lower <= upper else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }

    private func isConcealed(_ characterIndex: Int) -> Bool {
        guard !concealedRanges.isEmpty else { return false }
        var low = 0
        var high = concealedRanges.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let range = concealedRanges[mid]
            if characterIndex < range.location {
                high = mid - 1
            } else if characterIndex >= NSMaxRange(range) {
                low = mid + 1
            } else {
                return true
            }
        }
        return false
    }

    // MARK: - Glyph generation

    public override func setGlyphs(
        _ glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: PlatformFont,
        forGlyphRange glyphRange: NSRange
    ) {
        guard !concealedRanges.isEmpty, glyphRange.length > 0 else {
            super.setGlyphs(glyphs, properties: props, characterIndexes: charIndexes,
                            font: aFont, forGlyphRange: glyphRange)
            return
        }

        var adjusted = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        var touched = false
        for offset in 0..<glyphRange.length where isConcealed(charIndexes[offset]) {
            adjusted[offset].insert(.null)
            touched = true
        }

        guard touched else {
            super.setGlyphs(glyphs, properties: props, characterIndexes: charIndexes,
                            font: aFont, forGlyphRange: glyphRange)
            return
        }

        adjusted.withUnsafeBufferPointer { buffer in
            super.setGlyphs(glyphs, properties: buffer.baseAddress!, characterIndexes: charIndexes,
                            font: aFont, forGlyphRange: glyphRange)
        }
    }

    // MARK: - Decoration drawing

    public override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let container = textContainers.first, !decorations.isEmpty else {
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
            return
        }

        let storageLength = textStorage?.length ?? 0
        let visibleCharacters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        for decoration in decorations {
            let clamped = NSRange(
                location: min(decoration.range.location, storageLength),
                length: min(decoration.range.length, max(0, storageLength - decoration.range.location))
            )
            guard clamped.length > 0 || decoration.style == .rule else { continue }
            guard NSIntersectionRange(clamped, visibleCharacters).length > 0
                    || NSLocationInRange(clamped.location, visibleCharacters) else { continue }

            let glyphRange = self.glyphRange(forCharacterRange: clamped, actualCharacterRange: nil)
            var rect = boundingRect(forGlyphRange: glyphRange, in: container)
            rect.origin.x += origin.x
            rect.origin.y += origin.y

            switch decoration.style {
            case .codeBlock(let language):
                // The fences are folded away, so the panel's breathing room is
                // padding around the code rather than the blank lines they left.
                let panel = fullWidth(rect, container: container, origin: origin).insetBy(dx: 0, dy: -7)
                drawPanel(in: panel,
                          fill: MarkdownTheme.codeBackground,
                          stroke: MarkdownTheme.separator,
                          radius: 6)
                drawLanguage(language, in: panel)

            case .table:
                drawPanel(in: fullWidth(rect, container: container, origin: origin).insetBy(dx: 0, dy: -2),
                          fill: MarkdownTheme.codeBackground.withAlphaComponent(0.6),
                          stroke: MarkdownTheme.separator,
                          radius: 6)

            case .grid(let grid):
                // The first row's line was made exactly as tall as the grid;
                // its last glyph, the line break, is the one known to be on it.
                guard glyphRange.length > 0 else { continue }
                let line = lineFragmentRect(forGlyphAt: NSMaxRange(glyphRange) - 1, effectiveRange: nil)
                TableLayout.draw(grid, at: CGPoint(
                    x: origin.x + container.lineFragmentPadding,
                    y: origin.y + line.minY + grid.margin
                ))

            case .quote(let depth):
                for level in 0..<max(1, depth) {
                    let x = rect.minX + CGFloat(level) * 14
                    let bar = CGRect(x: x, y: rect.minY, width: 3, height: rect.height)
                    MarkdownTheme.quoteBar.setFill()
                    Platform.roundedPath(bar, radius: 1.5).fill()
                }

            case .rule:
                // Same anchoring as a grid: measure the line the break is on.
                guard glyphRange.length > 0 else { continue }
                var ruleRect = lineFragmentRect(forGlyphAt: NSMaxRange(glyphRange) - 1, effectiveRange: nil)
                ruleRect.origin.x += origin.x
                ruleRect.origin.y += origin.y
                let wide = fullWidth(ruleRect, container: container, origin: origin)
                let line = CGRect(x: wide.minX, y: wide.midY - 0.5, width: wide.width, height: 1)
                MarkdownTheme.separator.setFill()
                PlatformBezierPath(rect: line).fill()
            }
        }

        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func fullWidth(_ rect: CGRect, container: NSTextContainer, origin: CGPoint) -> CGRect {
        let padding = container.lineFragmentPadding
        return CGRect(
            x: origin.x + padding,
            y: rect.minY,
            width: max(0, container.size.width - padding * 2),
            height: rect.height
        )
    }

    /// The fenced language, small and quiet in the panel's top-right corner.
    private func drawLanguage(_ language: String, in panel: CGRect) {
        let name = language.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, panel.height > 28 else { return }
        let label = NSAttributedString(string: name, attributes: [
            .font: PlatformFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: MarkdownTheme.marker
        ])
        let size = label.size()
        label.draw(at: CGPoint(x: panel.maxX - size.width - 8, y: panel.minY + 4))
    }

    private func drawPanel(in rect: CGRect, fill: PlatformColor, stroke: PlatformColor, radius: CGFloat) {
        guard rect.width > 0, rect.height > 0 else { return }
        let path = Platform.roundedPath(rect, radius: radius)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
