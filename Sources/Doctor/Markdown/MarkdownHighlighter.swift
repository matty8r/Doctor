import AppKit
import DoctorMarkdown

/// Block-level decorations the layout manager draws behind the text: the things
/// that make preview mode look rendered rather than merely coloured.
struct BlockDecoration {
    enum Style: Equatable {
        case codeBlock
        case quote(depth: Int)
        case rule
        /// A table shown as source, while it's being edited or in Source mode.
        case table
        /// A table drawn as a grid, in the line the first row reserves for it.
        case grid(TableGrid)
    }
    var range: NSRange
    var style: Style
}

struct HighlightResult {
    var concealed: [NSRange]
    var decorations: [BlockDecoration]
}

/// Turns Markdown source into a styled `NSTextStorage` in place.
///
/// This runs on every keystroke, so it does one linear pass for block structure
/// and one regex pass per text-bearing line. On documents past a few hundred
/// kilobytes the inline pass is dropped rather than allowed to stutter.
enum MarkdownHighlighter {

    static let inlinePassLimit = 400_000

    static func highlight(
        storage: NSTextStorage,
        mode: EditorMode,
        revealRange: NSRange,
        settings: AppSettings,
        containerWidth: CGFloat = 0
    ) -> HighlightResult {
        let theme = MarkdownTheme(settings: settings, mode: mode)
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)

        let conceal = (mode == .preview) && settings.hideSyntax
        var concealed: [NSRange] = []
        var decorations: [BlockDecoration] = []

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.setAttributes(baseAttributes(theme: theme), range: full)
        guard full.length > 0 else { return HighlightResult(concealed: [], decorations: []) }

        let tokens = MarkdownSyntax.scan(text)
        let source = storage.string
        let doInline = text.length <= inlinePassLimit

        // Tables are found up front, because how a row is styled depends on
        // the whole table: it's drawn as a grid unless the caret is in any of
        // its rows, and then all of them go back to being source.
        let tables = tableGroups(in: tokens)
        var tableOfToken: [Int: Int] = [:]
        var renderTable: [Bool] = []
        var editingTable: [Bool] = []
        for (number, group) in tables.enumerated() {
            for index in group { tableOfToken[index] = number }
            let range = NSRange(location: tokens[group.lowerBound].range.location,
                                length: NSMaxRange(tokens[group.upperBound - 1].range) - tokens[group.lowerBound].range.location)
            let editing = touches(revealRange, range)
            editingTable.append(editing)
            renderTable.append(conceal && containerWidth > 0 && group.count >= 2
                && tokens[group.lowerBound + 1].kind == .tableDelimiter
                && !editing)
        }

        // Track open blocks so code fences get one decoration each rather than
        // one per line.
        var codeBlockStart: Int?
        var quoteRun: (start: Int, end: Int, depth: Int)?

        func flushQuote() {
            if let run = quoteRun {
                decorations.append(BlockDecoration(
                    range: NSRange(location: run.start, length: run.end - run.start),
                    style: .quote(depth: run.depth)
                ))
                quoteRun = nil
            }
        }

        func finishTable(_ number: Int) {
            let group = tables[number]
            let rows = Array(tokens[group])
            let first = rows[0].range.location
            let last = rows[rows.count - 1].range
            let span = NSRange(location: first, length: min(full.length, NSMaxRange(last) + 1) - first)

            if renderTable[number],
               let grid = TableLayout.grid(rows: rows, storage: storage, theme: theme,
                                           availableWidth: containerWidth - 2) {
                // The source rows vanish; the first keeps a line exactly as
                // tall as the grid, and the rest fold to nothing beneath it.
                for (offset, row) in rows.enumerated() {
                    concealed.append(row.range)
                    let style = NSMutableParagraphStyle()
                    let height = offset == 0 ? grid.reservedHeight : 0.01
                    style.minimumLineHeight = height
                    style.maximumLineHeight = height
                    storage.addAttribute(.paragraphStyle, value: style,
                                         range: NSRange(location: row.range.location,
                                                        length: min(full.length, NSMaxRange(row.range) + 1) - row.range.location))
                }
                // The range runs through the first row's line break: its
                // concealed characters can sit on the line above, but the break
                // is always on the line that was made tall.
                let anchor = NSRange(location: rows[0].range.location,
                                     length: min(full.length, NSMaxRange(rows[0].range) + 1) - rows[0].range.location)
                decorations.append(BlockDecoration(range: anchor, style: .grid(grid)))
            } else {
                decorations.append(BlockDecoration(range: span, style: .table))
            }
        }

        for (tokenIndex, token) in tokens.enumerated() {
            let lineRange = token.range
            let table = tableOfToken[tokenIndex]
            let isRendered = table.map { renderTable[$0] } ?? false
            // A table being edited is source in full, delimiter row included:
            // editing one row of a table means reading the others as source too.
            let isRevealed = !conceal || touches(revealRange, lineRange)
                || (table.map { editingTable[$0] } ?? false)

            // -- Blockquote runs -------------------------------------------------
            if token.quoteDepth > 0 {
                if var run = quoteRun, run.depth == token.quoteDepth {
                    run.end = NSMaxRange(lineRange) + 1
                    quoteRun = run
                } else {
                    flushQuote()
                    quoteRun = (lineRange.location, NSMaxRange(lineRange) + 1, token.quoteDepth)
                }
            } else if token.kind != .blank {
                flushQuote()
            }

            let paragraph = paragraphStyle(for: token, theme: theme)
            storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)

            // -- Markers ----------------------------------------------------------
            for marker in token.markers where marker.length > 0 {
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.marker, range: marker)
                if conceal && !isRevealed && concealableLineMarker(token.kind) {
                    concealed.append(marker)
                }
            }

            // -- Block styling ------------------------------------------------------
            switch token.kind {
            case .blank:
                break

            case .heading(let level):
                storage.addAttribute(.font, value: theme.headingFont(level: level), range: lineRange)
                storage.addAttribute(
                    .foregroundColor,
                    value: level >= 5 ? MarkdownTheme.secondary : MarkdownTheme.heading,
                    range: token.content
                )

            case .setextUnderline:
                // The scanner has already promoted the line above to a heading;
                // the row of "=" or "-" is pure punctuation.
                if conceal && !isRevealed { concealed.append(lineRange) }

            case .fenceOpen:
                if codeBlockStart == nil { codeBlockStart = lineRange.location }
                storage.addAttribute(.font, value: labelFont(theme), range: lineRange)
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.secondary, range: token.content)

            case .fenceClose:
                if let start = codeBlockStart {
                    decorations.append(BlockDecoration(
                        range: NSRange(location: start, length: NSMaxRange(lineRange) - start),
                        style: .codeBlock
                    ))
                    codeBlockStart = nil
                }
                storage.addAttribute(.font, value: labelFont(theme), range: lineRange)
                if conceal && !isRevealed { concealed.append(lineRange) }

            case .codeLine, .indentedCode:
                if token.kind == .indentedCode, codeBlockStart == nil {
                    codeBlockStart = lineRange.location
                }
                storage.addAttribute(.font, value: theme.monospaceFont, range: lineRange)
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.text, range: lineRange)

            case .horizontalRule:
                if conceal && !isRevealed {
                    concealed.append(lineRange)
                    // Anchored through the line break: the hidden dashes have no
                    // glyphs of their own and would otherwise be found on the
                    // line above, which is where the rule would then be drawn.
                    decorations.append(BlockDecoration(
                        range: NSRange(location: lineRange.location,
                                       length: min(full.length, NSMaxRange(lineRange) + 1) - lineRange.location),
                        style: .rule
                    ))
                } else {
                    // Showing the dashes and drawing a rule through them says the
                    // same thing twice, so while it's source it stays source.
                    storage.addAttribute(.foregroundColor, value: MarkdownTheme.marker, range: lineRange)
                }

            case .frontmatterFence, .frontmatterLine:
                storage.addAttribute(.font, value: labelFont(theme), range: lineRange)
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.secondary, range: lineRange)

            case .tableRow, .tableDelimiter:
                // Monospace keeps the columns lined up while you edit them. A
                // table drawn as a grid keeps body text, which the grid's cells
                // are built from.
                if !isRendered {
                    storage.addAttribute(.font, value: theme.monospaceFont, range: lineRange)
                }
                if token.kind == .tableDelimiter {
                    storage.addAttribute(.foregroundColor, value: MarkdownTheme.marker, range: lineRange)
                }

            case .bullet, .ordered:
                break

            case .task(let checked):
                if checked {
                    storage.addAttribute(.strikethroughStyle,
                                         value: NSUnderlineStyle.single.rawValue, range: token.content)
                    storage.addAttribute(.foregroundColor, value: MarkdownTheme.secondary, range: token.content)
                }
                if let box = token.markers.last {
                    storage.addAttribute(.foregroundColor, value: MarkdownTheme.accent, range: box)
                }

            case .paragraph:
                break
            }

            // -- Inline spans --------------------------------------------------------
            if doInline, token.content.length > 0, inlineEligible(token.kind) {
                let spans = MarkdownSyntax.inlineTokens(in: text, source: source, range: token.content)
                for span in spans {
                    applyInline(span, to: storage, theme: theme, mode: mode)
                    if conceal && (!isRevealed || isRendered) {
                        concealed.append(contentsOf: span.markers)
                        if let destination = span.destination { concealed.append(destination) }
                    } else {
                        for marker in span.markers {
                            storage.addAttribute(.foregroundColor, value: MarkdownTheme.marker, range: marker)
                        }
                        if let destination = span.destination {
                            storage.addAttribute(.foregroundColor, value: MarkdownTheme.secondary, range: destination)
                        }
                    }
                }
            }

            // Cells are built from the finished styling, so a table is laid
            // out once its last row has been through the inline pass.
            if let table, tables[table].upperBound - 1 == tokenIndex {
                finishTable(table)
            }
        }

        flushQuote()
        if let start = codeBlockStart {
            // An unterminated fence still deserves its background.
            decorations.append(BlockDecoration(
                range: NSRange(location: start, length: full.length - start),
                style: .codeBlock
            ))
        }

        return HighlightResult(concealed: merge(concealed), decorations: decorations)
    }

    // MARK: - Attributes

    /// True when the caret or selection sits anywhere on this line, including at
    /// its very end. That line keeps its punctuation so you can edit it.
    private static func touches(_ selection: NSRange, _ line: NSRange) -> Bool {
        if NSIntersectionRange(selection, line).length > 0 { return true }
        return selection.location >= line.location && selection.location <= NSMaxRange(line)
    }

    private static func baseAttributes(theme: MarkdownTheme) -> [NSAttributedString.Key: Any] {
        [
            .font: theme.baseFont,
            .foregroundColor: MarkdownTheme.text
        ]
    }

    private static func labelFont(_ theme: MarkdownTheme) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: theme.baseSize * 0.8, weight: .medium)
    }

    private static func inlineEligible(_ kind: LineKind) -> Bool {
        switch kind {
        case .codeLine, .indentedCode, .fenceOpen, .fenceClose,
             .frontmatterLine, .frontmatterFence, .horizontalRule,
             .tableDelimiter, .blank, .setextUnderline:
            return false
        default:
            return true
        }
    }

    /// Which line-level punctuation disappears in preview. List bullets and task
    /// boxes stay: hiding them would leave the list with nothing to read as a list.
    private static func concealableLineMarker(_ kind: LineKind) -> Bool {
        switch kind {
        case .bullet, .ordered, .task:
            return false
        default:
            return true
        }
    }

    private static func applyInline(
        _ span: InlineToken,
        to storage: NSTextStorage,
        theme: MarkdownTheme,
        mode: EditorMode
    ) {
        let content = span.content
        guard content.location != NSNotFound, content.length >= 0 else { return }

        func currentFont(at range: NSRange) -> NSFont {
            guard range.length > 0,
                  let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            else { return theme.baseFont }
            return font
        }

        switch span.kind {
        case .code:
            storage.addAttribute(.font, value: theme.monospaceFont, range: span.range)
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.codeText, range: content)
            storage.addAttribute(.backgroundColor, value: MarkdownTheme.codeBackground, range: span.range)

        case .strong:
            storage.addAttribute(.font, value: theme.applying(traits: .bold, to: currentFont(at: content)), range: content)

        case .emphasis:
            storage.addAttribute(.font, value: theme.applying(traits: .italic, to: currentFont(at: content)), range: content)

        case .strongEmphasis:
            let font = theme.applying(traits: [.bold, .italic], to: currentFont(at: content))
            storage.addAttribute(.font, value: font, range: content)

        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: content)
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.secondary, range: content)

        case .highlight:
            storage.addAttribute(.backgroundColor, value: MarkdownTheme.highlightBackground, range: content)

        case .link, .wikiLink, .autolink, .bareURL:
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.accent, range: content)
            if mode == .preview {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: content)
                storage.addAttribute(.underlineColor,
                                     value: MarkdownTheme.accent.withAlphaComponent(0.45), range: content)
            }

        case .image:
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.secondary, range: content)

        case .tag:
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.tagColor, range: span.range)

        case .footnoteRef:
            storage.addAttribute(.foregroundColor, value: MarkdownTheme.accent, range: span.range)
            storage.addAttribute(.baselineOffset, value: theme.baseSize * 0.25, range: span.range)
            storage.addAttribute(.font, value: labelFont(theme), range: span.range)
        }
    }

    private static func paragraphStyle(for token: LineToken, theme: MarkdownTheme) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = theme.lineHeightMultiple

        let quoteInset = CGFloat(token.quoteDepth) * theme.baseSize * 1.2
        var firstLine = quoteInset
        var wrapped = quoteInset

        switch token.kind {
        case .heading(let level), .setextUnderline(let level):
            style.paragraphSpacingBefore = level <= 2 ? theme.baseSize * 1.1 : theme.baseSize * 0.8
            style.paragraphSpacing = theme.baseSize * 0.35
            style.lineHeightMultiple = max(1.0, theme.lineHeightMultiple * 0.9)

        case .bullet, .ordered, .task:
            // Nesting is usually two or four spaces; either maps to one step.
            let level = min(6, token.indent / 2)
            firstLine += CGFloat(level) * theme.listIndentWidth
            wrapped = firstLine + theme.listIndentWidth
            style.paragraphSpacing = theme.paragraphSpacing * 0.25

        case .codeLine, .indentedCode, .fenceOpen, .fenceClose:
            style.lineHeightMultiple = 1.15
            firstLine += theme.baseSize * 0.7
            wrapped = firstLine

        case .tableRow, .tableDelimiter:
            style.lineHeightMultiple = 1.15
            firstLine += theme.baseSize * 0.5
            // A long row's continuation hangs, so each row still starts at the
            // margin and reads as one row.
            wrapped = firstLine + theme.baseSize * 1.5

        case .horizontalRule:
            style.paragraphSpacingBefore = theme.baseSize * 0.5
            style.paragraphSpacing = theme.baseSize * 0.5

        case .paragraph:
            style.paragraphSpacing = theme.paragraphSpacing

        default:
            style.paragraphSpacing = theme.paragraphSpacing * 0.5
        }

        style.firstLineHeadIndent = firstLine
        style.headIndent = wrapped
        return style
    }

    // MARK: - Tables

    /// Runs of consecutive table lines, as index ranges into `tokens`.
    private static func tableGroups(in tokens: [LineToken]) -> [Range<Int>] {
        var groups: [Range<Int>] = []
        var start: Int?
        for (index, token) in tokens.enumerated() {
            let isTable = token.kind == .tableRow || token.kind == .tableDelimiter
            if isTable, start == nil { start = index }
            if !isTable, let open = start {
                groups.append(open..<index)
                start = nil
            }
        }
        if let open = start { groups.append(open..<tokens.count) }
        return groups
    }

    // MARK: - Range bookkeeping

    /// Concealed ranges are consulted per glyph, so they are sorted and coalesced
    /// once here to keep that lookup a binary search over a small array.
    private static func merge(_ ranges: [NSRange]) -> [NSRange] {
        guard !ranges.isEmpty else { return [] }
        let sorted = ranges.filter { $0.length > 0 }.sorted { $0.location < $1.location }
        guard !sorted.isEmpty else { return [] }

        var merged: [NSRange] = [sorted[0]]
        for range in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            if range.location <= NSMaxRange(last) {
                let end = max(NSMaxRange(last), NSMaxRange(range))
                merged[merged.count - 1] = NSRange(location: last.location, length: end - last.location)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
