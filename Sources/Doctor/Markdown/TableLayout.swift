import AppKit
import DoctorMarkdown

/// A Markdown table as preview mode draws it: real columns that wrap, rather
/// than a block of pipes.
///
/// The source rows stay in the text storage untouched. The highlighter conceals
/// them and gives the first row a line tall enough to hold the grid, and the
/// layout manager paints this into that space. Put the caret in the table and
/// it goes back to being source, like any other line being edited.
struct TableGrid: Equatable {
    /// Header row first. Every row has one entry per column.
    var cells: [[NSAttributedString]]
    var columnWidths: [CGFloat]
    var rowHeights: [CGFloat]
    var padding: NSSize
    /// Space above and below the grid, inside the line that reserves it.
    var margin: CGFloat

    var width: CGFloat { columnWidths.reduce(0, +) }
    var height: CGFloat { rowHeights.reduce(0, +) }
    /// The height of the line that holds the grid.
    var reservedHeight: CGFloat { (height + margin * 2).rounded(.up) }
}

enum ColumnAlignment {
    case left, center, right

    var textAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}

enum TableLayout {

    // MARK: - Parsing

    /// The content of each cell in a table row, trimmed, as ranges in `text`.
    /// Pipes inside backticks and escaped pipes don't separate cells.
    static func cells(in text: NSString, line: NSRange) -> [NSRange] {
        let pipe = unichar(UInt8(ascii: "|"))
        let tick = unichar(UInt8(ascii: "`"))
        let backslash = unichar(UInt8(ascii: "\\"))

        var pipes: [Int] = []
        var inCode = false
        var index = line.location
        while index < NSMaxRange(line) {
            let c = text.character(at: index)
            if c == backslash { index += 2; continue }
            if c == tick { inCode.toggle() }
            if c == pipe && !inCode { pipes.append(index) }
            index += 1
        }

        let content = trimmed(NSRange(location: line.location, length: line.length), in: text)
        var start = content.location
        var end = NSMaxRange(content)
        var interior = pipes
        if let first = interior.first, first == content.location {
            start = first + 1
            interior.removeFirst()
        }
        if let last = interior.last, last == NSMaxRange(content) - 1, last >= start {
            end = last
            interior.removeLast()
        }

        var result: [NSRange] = []
        var cellStart = start
        for boundary in interior where boundary >= start && boundary < end {
            result.append(trimmed(NSRange(location: cellStart, length: boundary - cellStart), in: text))
            cellStart = boundary + 1
        }
        result.append(trimmed(NSRange(location: cellStart, length: max(0, end - cellStart)), in: text))
        return result
    }

    static func alignments(in text: NSString, delimiter: NSRange) -> [ColumnAlignment] {
        cells(in: text, line: delimiter).map { range in
            let spec = text.substring(with: range)
            switch (spec.hasPrefix(":"), spec.hasSuffix(":")) {
            case (true, true): return .center
            case (false, true): return .right
            default: return .left
            }
        }
    }

    private static func trimmed(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, isSpace(text.character(at: start)) { start += 1 }
        while end > start, isSpace(text.character(at: end - 1)) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    private static func isSpace(_ c: unichar) -> Bool {
        c == 0x20 || c == 0x09
    }

    // MARK: - Layout

    /// Builds the grid for `rows` (header, delimiter, body…) from the storage's
    /// current attributes, so inline styling inside cells carries over. Returns
    /// nil when the rows aren't a well-formed table.
    static func grid(
        rows: [LineToken],
        storage: NSTextStorage,
        theme: MarkdownTheme,
        availableWidth: CGFloat
    ) -> TableGrid? {
        guard rows.count >= 2, rows[1].kind == .tableDelimiter, availableWidth > 60 else { return nil }
        let text = storage.string as NSString
        let source = storage.string

        let header = cells(in: text, line: rows[0].range)
        let columns = header.count
        guard columns > 0 else { return nil }
        let aligns = alignments(in: text, delimiter: rows[1].range)

        let lines = [rows[0]] + rows.dropFirst(2)
        let cells: [[NSAttributedString]] = lines.enumerated().map { rowIndex, row in
            let ranges = rowIndex == 0 ? header : self.cells(in: text, line: row.range)
            return (0..<columns).map { column in
                let align = column < aligns.count ? aligns[column] : .left
                guard column < ranges.count else { return NSAttributedString() }
                return displayString(for: ranges[column], storage: storage, source: source,
                                     theme: theme, alignment: align, isHeader: rowIndex == 0)
            }
        }

        let padding = NSSize(width: (theme.baseSize * 0.7).rounded(), height: (theme.baseSize * 0.4).rounded())
        let widths = columnWidths(for: cells, columns: columns, padding: padding.width, available: availableWidth)
        let heights = cells.map { row in
            zip(row, widths).map { cell, width in
                measuredHeight(cell, width: width - padding.width * 2, theme: theme) + padding.height * 2
            }.max() ?? 0
        }

        return TableGrid(cells: cells, columnWidths: widths, rowHeights: heights,
                         padding: padding, margin: (theme.baseSize * 0.5).rounded())
    }

    /// The cell as it should read: inline punctuation removed, styling kept.
    private static func displayString(
        for range: NSRange,
        storage: NSTextStorage,
        source: String,
        theme: MarkdownTheme,
        alignment: ColumnAlignment,
        isHeader: Bool
    ) -> NSAttributedString {
        guard range.length > 0 else { return NSAttributedString() }
        let text = storage.string as NSString

        var hidden: [NSRange] = []
        for span in MarkdownSyntax.inlineTokens(in: text, source: source, range: range) {
            hidden.append(contentsOf: span.markers)
            if let destination = span.destination { hidden.append(destination) }
        }
        // An escaped pipe reads as a pipe.
        var search = range
        while true {
            let found = text.range(of: "\\|", options: [], range: search)
            guard found.location != NSNotFound else { break }
            hidden.append(NSRange(location: found.location, length: 1))
            search = NSRange(location: NSMaxRange(found), length: NSMaxRange(range) - NSMaxRange(found))
        }

        let result = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        for cut in hidden.sorted(by: { $0.location > $1.location }) {
            let local = NSIntersectionRange(cut, range)
            guard local.length > 0 else { continue }
            result.deleteCharacters(in: NSRange(location: local.location - range.location, length: local.length))
        }

        let full = NSRange(location: 0, length: result.length)
        let style = NSMutableParagraphStyle()
        style.alignment = alignment.textAlignment
        style.lineBreakMode = .byWordWrapping
        style.lineHeightMultiple = 1.1
        result.addAttribute(.paragraphStyle, value: style, range: full)
        result.removeAttribute(.backgroundColor, range: full)

        if isHeader {
            result.enumerateAttribute(.font, in: full) { value, sub, _ in
                let font = (value as? NSFont) ?? theme.baseFont
                result.addAttribute(.font, value: theme.applying(traits: .bold, to: font), range: sub)
            }
        }
        return result
    }

    /// Columns get their natural width when the table fits. When it doesn't,
    /// each keeps at least its longest word and the rest of the room goes to
    /// the columns with the most text, so wide columns wrap and narrow ones
    /// don't — roughly what a browser does with an HTML table.
    private static func columnWidths(
        for cells: [[NSAttributedString]],
        columns: Int,
        padding: CGFloat,
        available: CGFloat
    ) -> [CGFloat] {
        var natural = [CGFloat](repeating: 0, count: columns)
        var minimum = [CGFloat](repeating: 0, count: columns)
        for row in cells {
            for (column, cell) in row.enumerated() {
                natural[column] = max(natural[column], singleLineWidth(cell))
                minimum[column] = max(minimum[column], longestWordWidth(cell))
            }
        }
        let gutter = padding * 2
        let floor = gutter + padding * 1.5
        natural = natural.map { max(floor, ($0 + gutter).rounded(.up)) }
        minimum = minimum.map { max(floor, ($0 + gutter).rounded(.up)) }

        if natural.reduce(0, +) <= available { return natural }

        let minimumTotal = minimum.reduce(0, +)
        if minimumTotal >= available {
            // Even word by word it doesn't fit: shrink proportionally and let
            // long words break.
            return minimum.map { ($0 / minimumTotal * available).rounded(.down) }
        }

        let slack = available - minimumTotal
        let want = zip(natural, minimum).map { $0 - $1 }
        let wantTotal = want.reduce(0, +)
        return zip(minimum, want).map { min, extra in
            (min + (wantTotal > 0 ? extra / wantTotal * slack : 0)).rounded(.down)
        }
    }

    private static func singleLineWidth(_ string: NSAttributedString) -> CGFloat {
        guard string.length > 0 else { return 0 }
        return string.boundingRect(with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                                   options: [.usesLineFragmentOrigin]).width
    }

    private static func longestWordWidth(_ string: NSAttributedString) -> CGFloat {
        let text = string.string as NSString
        var widest: CGFloat = 0
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byWords) { _, range, enclosing, _ in
            // Measure through trailing punctuation, which wraps with its word.
            let word = NSRange(location: range.location, length: max(range.length, NSMaxRange(enclosing) - range.location))
            let trimmed = (text.substring(with: word) as NSString)
                .trimmingCharacters(in: .whitespaces) as NSString
            let piece = string.attributedSubstring(from: NSRange(location: word.location, length: trimmed.length))
            widest = max(widest, singleLineWidth(piece))
        }
        return widest
    }

    private static func measuredHeight(_ string: NSAttributedString, width: CGFloat, theme: MarkdownTheme) -> CGFloat {
        guard string.length > 0 else { return theme.baseFont.boundingRectForFont.height * 0.75 }
        return string.boundingRect(with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
                                   options: [.usesLineFragmentOrigin, .usesFontLeading]).height.rounded(.up)
    }

    // MARK: - Drawing

    /// Paints `grid` with its top-left corner at `origin`.
    static func draw(_ grid: TableGrid, at origin: NSPoint) {
        let frame = NSRect(x: origin.x, y: origin.y, width: grid.width, height: grid.height)
        guard frame.width > 0, frame.height > 0 else { return }
        let outline = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()

        // Header band.
        if let headerHeight = grid.rowHeights.first {
            MarkdownTheme.codeBackground.setFill()
            NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: headerHeight).fill()
        }

        // Rules between rows, stronger under the header.
        var y = frame.minY
        for (index, height) in grid.rowHeights.enumerated() {
            y += height
            guard index < grid.rowHeights.count - 1 else { break }
            (index == 0 ? MarkdownTheme.marker : MarkdownTheme.separator).setFill()
            NSRect(x: frame.minX, y: y - 0.5, width: frame.width, height: 1).fill()
        }

        // Rules between columns.
        MarkdownTheme.separator.setFill()
        var x = frame.minX
        for width in grid.columnWidths.dropLast() {
            x += width
            NSRect(x: x - 0.5, y: frame.minY, width: 1, height: frame.height).fill()
        }

        // Cells.
        y = frame.minY
        for (row, height) in zip(grid.cells, grid.rowHeights) {
            x = frame.minX
            for (cell, width) in zip(row, grid.columnWidths) {
                let box = NSRect(x: x + grid.padding.width, y: y + grid.padding.height,
                                 width: width - grid.padding.width * 2, height: height - grid.padding.height * 2)
                cell.draw(with: box, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
                x += width
            }
            y += height
        }
        NSGraphicsContext.restoreGraphicsState()

        MarkdownTheme.separator.setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }
}
