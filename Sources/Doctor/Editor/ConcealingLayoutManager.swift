import AppKit

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
final class ConcealingLayoutManager: NSLayoutManager {

    /// Sorted, non-overlapping ranges whose glyphs should vanish.
    private(set) var concealedRanges: [NSRange] = []
    private(set) var decorations: [BlockDecoration] = []

    // MARK: - State

    func update(concealed: [NSRange], decorations: [BlockDecoration]) {
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

        // Decorations are painted, not laid out, so they only need a redraw.
        firstTextView?.needsDisplay = true
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

    override func setGlyphs(
        _ glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
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

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
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
            case .codeBlock:
                drawPanel(in: fullWidth(rect, container: container, origin: origin).insetBy(dx: 0, dy: -2),
                          fill: MarkdownTheme.codeBackground,
                          stroke: MarkdownTheme.separator,
                          radius: 6)

            case .table:
                drawPanel(in: fullWidth(rect, container: container, origin: origin).insetBy(dx: 0, dy: -2),
                          fill: MarkdownTheme.codeBackground.withAlphaComponent(0.6),
                          stroke: MarkdownTheme.separator,
                          radius: 6)

            case .quote(let depth):
                for level in 0..<max(1, depth) {
                    let x = rect.minX + CGFloat(level) * 14
                    let bar = NSRect(x: x, y: rect.minY, width: 3, height: rect.height)
                    MarkdownTheme.quoteBar.setFill()
                    NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
                }

            case .rule:
                let wide = fullWidth(rect, container: container, origin: origin)
                let line = NSRect(x: wide.minX, y: wide.midY - 0.5, width: wide.width, height: 1)
                MarkdownTheme.separator.setFill()
                NSBezierPath(rect: line).fill()
            }
        }

        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func fullWidth(_ rect: NSRect, container: NSTextContainer, origin: NSPoint) -> NSRect {
        let padding = container.lineFragmentPadding
        return NSRect(
            x: origin.x + padding,
            y: rect.minY,
            width: max(0, container.size.width - padding * 2),
            height: rect.height
        )
    }

    private func drawPanel(in rect: NSRect, fill: NSColor, stroke: NSColor, radius: CGFloat) {
        guard rect.width > 0, rect.height > 0 else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
