import AppKit
import DoctorMarkdown

/// Block-level decorations the layout manager draws behind the text: the things
/// that make preview mode look rendered rather than merely coloured.
struct BlockDecoration {
    enum Style: Equatable {
        case codeBlock
        case quote(depth: Int)
        case rule
        case table
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
        settings: AppSettings
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

        // Track open blocks so code fences and tables get one decoration each
        // rather than one per line.
        var codeBlockStart: Int?
        var tableStart: Int?
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

        func flushTable(endingAt end: Int) {
            if let start = tableStart {
                decorations.append(BlockDecoration(
                    range: NSRange(location: start, length: max(0, end - start)),
                    style: .table
                ))
                tableStart = nil
            }
        }

        for token in tokens {
            let lineRange = token.range
            let isRevealed = !conceal || touches(revealRange, lineRange)

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
                decorations.append(BlockDecoration(range: lineRange, style: .rule))
                if conceal && !isRevealed {
                    concealed.append(lineRange)
                } else {
                    storage.addAttribute(.foregroundColor, value: MarkdownTheme.marker, range: lineRange)
                }

            case .frontmatterFence, .frontmatterLine:
                storage.addAttribute(.font, value: labelFont(theme), range: lineRange)
                storage.addAttribute(.foregroundColor, value: MarkdownTheme.secondary, range: lineRange)

            case .tableRow, .tableDelimiter:
                if tableStart == nil { tableStart = lineRange.location }
                // Monospace keeps the columns lined up while you edit them.
                storage.addAttribute(.font, value: theme.monospaceFont, range: lineRange)
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

            if !token.kind.isCode && token.kind != .tableRow && token.kind != .tableDelimiter {
                flushTable(endingAt: lineRange.location)
            }

            // -- Inline spans --------------------------------------------------------
            if doInline, token.content.length > 0, inlineEligible(token.kind) {
                let spans = MarkdownSyntax.inlineTokens(in: text, source: source, range: token.content)
                for span in spans {
                    applyInline(span, to: storage, theme: theme, mode: mode)
                    if conceal && !isRevealed {
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
        }

        flushQuote()
        flushTable(endingAt: full.length)
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
            wrapped = firstLine

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
