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

            case .checkbox(let checked, let indentWidth, let boxSize):
                guard let gap = reservedGap(forGlyphRange: glyphRange, origin: origin,
                                            container: container, indentWidth: indentWidth) else { continue }
                let box = CGRect(
                    x: gap.left + (indentWidth - boxSize) / 2,
                    y: gap.verticalCenter - boxSize / 2,
                    width: boxSize,
                    height: boxSize
                )
                drawCheckbox(box, checked: checked)

            case .bullet(let indentWidth, let dotSize):
                guard let gap = reservedGap(forGlyphRange: glyphRange, origin: origin,
                                            container: container, indentWidth: indentWidth) else { continue }
                let dot = CGRect(
                    x: gap.left + (indentWidth - dotSize) / 2,
                    y: gap.verticalCenter - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                MarkdownTheme.text.setFill()
                PlatformBezierPath(ovalIn: dot).fill()
            }
        }

        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    /// Where a list marker's reserved gap sits for a decoration anchored on
    /// `glyphRange` -- the item's visible content, not its concealed marker
    /// (a glyph range that's entirely null/concealed has no real glyph of
    /// its own to find a line fragment from, so `.checkbox` and `.bullet`
    /// both anchor on the content instead). `left` is the gap's left edge;
    /// combine with the decoration's own `indentWidth` to center a glyph in
    /// it horizontally. `verticalCenter` is where to center one vertically —
    /// deliberately *not* the line fragment's own midpoint: that box
    /// includes `lineHeightMultiple` leading, which isn't symmetric around
    /// the glyphs themselves, and centering a checkbox or dot against it
    /// visibly floats the glyph above the text it labels (seen directly on
    /// a real device, reported as "I'd expect the checkboxes to be center
    /// aligned with the text"). Centered on the text's cap-height band
    /// instead -- baseline up by half the font's cap height -- which is
    /// where a reader's eye actually reads text as vertically centered.
    private func reservedGap(
        forGlyphRange glyphRange: NSRange, origin: CGPoint, container: NSTextContainer, indentWidth: CGFloat
    ) -> (left: CGFloat, verticalCenter: CGFloat)? {
        guard glyphRange.length > 0 else { return nil }
        var lineRect = lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        lineRect.origin.x += origin.x
        lineRect.origin.y += origin.y
        let charIndex = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil).location
        let headIndent = (textStorage?.attribute(.paragraphStyle, at: charIndex, effectiveRange: nil)
            as? NSParagraphStyle)?.headIndent ?? indentWidth
        let left = origin.x + container.lineFragmentPadding + headIndent - indentWidth

        let baselineY = lineRect.minY + location(forGlyphAt: glyphRange.location).y
        let font = textStorage?.attribute(.font, at: charIndex, effectiveRange: nil) as? PlatformFont
        let capHeight = font?.capHeight ?? (lineRect.height * 0.5)
        return (left, baselineY - capHeight / 2)
    }

    /// The task whose drawn checkbox contains `point` (text-container
    /// coordinates, i.e. a tap location with `textContainerInset` already
    /// subtracted out), if any. Lets a tap toggle the checkbox in place
    /// instead of the normal, here-wrong thing a tap on a text view does —
    /// just place the caret, which on a concealed task line also reveals its
    /// raw `- [ ] ` and leaves edit mode behind. Reuses the exact geometry
    /// `drawBackground` draws the checkbox with, so a hit always matches
    /// what's actually on screen.
    public func checkboxHit(at point: CGPoint, in container: NSTextContainer, origin: CGPoint = .zero) -> NSRange? {
        for decoration in decorations {
            guard case .checkbox(_, let indentWidth, let boxSize) = decoration.style,
                  decoration.range.length > 0
            else { continue }
            let glyphRange = self.glyphRange(forCharacterRange: decoration.range, actualCharacterRange: nil)
            guard let gap = reservedGap(forGlyphRange: glyphRange, origin: origin,
                                        container: container, indentWidth: indentWidth)
            else { continue }
            let box = CGRect(
                x: gap.left + (indentWidth - boxSize) / 2,
                y: gap.verticalCenter - boxSize / 2,
                width: boxSize,
                height: boxSize
            ).insetBy(dx: -8, dy: -8)
            if box.contains(point) { return decoration.range }
        }
        return nil
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

    /// Pure CoreGraphics rather than `PlatformBezierPath`, since a checkmark
    /// needs individual line segments and `NSBezierPath`/`UIBezierPath` spell
    /// "add a segment" differently (`line(to:)` vs `addLine(to:)`); `CGContext`
    /// itself doesn't.
    private func drawCheckbox(_ rect: CGRect, checked: Bool) {
        guard let context = Platform.currentCGContext else { return }
        context.saveGState()
        defer { context.restoreGState() }

        let corner = rect.width * 0.22
        let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

        if checked {
            context.addPath(path)
            context.setFillColor(MarkdownTheme.accent.cgColor)
            context.fillPath()

            context.setStrokeColor(PlatformColor.white.cgColor)
            context.setLineWidth(max(1.2, rect.width * 0.12))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.52))
            context.addLine(to: CGPoint(x: rect.minX + rect.width * 0.43, y: rect.minY + rect.height * 0.70))
            context.addLine(to: CGPoint(x: rect.minX + rect.width * 0.76, y: rect.minY + rect.height * 0.32))
            context.strokePath()
        } else {
            context.addPath(path)
            context.setStrokeColor(MarkdownTheme.marker.cgColor)
            context.setLineWidth(max(1.0, rect.width * 0.09))
            context.strokePath()
        }
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
