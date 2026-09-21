import Foundation

/// Renders Markdown to standalone HTML for printing, PDF export and HTML export.
///
/// This is a separate parser from `MarkdownSyntax`: the editor only needs to know
/// where things start, whereas printing needs real nesting. Trying to serve both
/// from one parser is how Markdown editors end up with a parser nobody can change.
///
/// Raw HTML in the source is escaped apart from a small whitelist of harmless
/// inline tags. Documents that arrive from the internet should not be able to
/// pull remote resources or run scripts just because you pressed Print.
public enum HTMLRenderer {

    // MARK: - Entry points

    public static func document(markdown: String, title: String, forPrint: Bool = true) -> String {
        let body = render(markdown: markdown)
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <title>\(escape(title))</title>
        <style>
        \(stylesheet(forPrint: forPrint))
        </style>
        </head>
        <body>
        <article class="doctor-document">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    public static func render(markdown: String) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")

        var prefix = ""
        // YAML frontmatter is metadata, not prose. Keep it, but set it apart.
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            if let close = lines.dropFirst().firstIndex(where: {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return t == "---" || t == "..."
            }) {
                let meta = lines[1..<close].joined(separator: "\n")
                prefix = "<pre class=\"frontmatter\">\(escape(meta))</pre>\n"
                lines = Array(lines[(close + 1)...])
            }
        }

        return prefix + renderBlocks(lines)
    }

    // MARK: - Block level

    private static func renderBlocks(_ lines: [String]) -> String {
        var out = ""
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { index += 1; continue }

            // Fenced code
            if let fence = fenceInfo(trimmed) {
                index += 1
                var body: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if let closing = fenceInfo(candidate),
                       closing.character == fence.character,
                       closing.length >= fence.length,
                       closing.info.isEmpty {
                        index += 1
                        break
                    }
                    body.append(lines[index])
                    index += 1
                }
                let languageClass = fence.info.isEmpty
                    ? ""
                    : " class=\"language-\(escapeAttribute(fence.info.components(separatedBy: " ").first ?? ""))\""
                out += "<pre><code\(languageClass)>\(escape(body.joined(separator: "\n")))</code></pre>\n"
                continue
            }

            // Thematic break
            if isHorizontalRule(trimmed) {
                out += "<hr>\n"
                index += 1
                continue
            }

            // ATX heading
            if let heading = atxHeading(trimmed) {
                let inner = inline(heading.text)
                out += "<h\(heading.level) id=\"\(slug(heading.text))\">\(inner)</h\(heading.level)>\n"
                index += 1
                continue
            }

            // Blockquote
            if isBlockquote(line) {
                var block: [String] = []
                while index < lines.count {
                    let candidate = lines[index]
                    if isBlockquote(candidate) {
                        block.append(stripQuoteMarker(candidate))
                        index += 1
                    } else if !candidate.trimmingCharacters(in: .whitespaces).isEmpty,
                              !block.isEmpty,
                              !startsNewBlock(candidate) {
                        // Lazy continuation of the previous quoted paragraph.
                        block.append(candidate)
                        index += 1
                    } else {
                        break
                    }
                }
                out += "<blockquote>\n\(renderBlocks(block))</blockquote>\n"
                continue
            }

            // Table
            if line.contains("|"), index + 1 < lines.count,
               MarkdownSyntax.isTableDelimiter(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
                var rows: [String] = [line]
                let alignments = tableAlignments(lines[index + 1])
                index += 2
                while index < lines.count {
                    let candidate = lines[index]
                    if candidate.trimmingCharacters(in: .whitespaces).isEmpty || !candidate.contains("|") { break }
                    rows.append(candidate)
                    index += 1
                }
                out += renderTable(rows: rows, alignments: alignments)
                continue
            }

            // List
            if listMarker(line) != nil {
                var block: [String] = []
                let baseIndent = indentWidth(line)
                while index < lines.count {
                    let candidate = lines[index]
                    let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)

                    if candidateTrimmed.isEmpty {
                        // A blank line only stays inside the list if the list resumes.
                        let next = lines[(index + 1)...].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        guard let next,
                              indentWidth(next) > baseIndent
                                || (listMarker(next) != nil && indentWidth(next) >= baseIndent)
                        else { break }
                        block.append("")
                        index += 1
                        continue
                    }

                    if listMarker(candidate) != nil && indentWidth(candidate) >= baseIndent {
                        block.append(candidate)
                        index += 1
                    } else if indentWidth(candidate) > baseIndent {
                        block.append(candidate)
                        index += 1
                    } else if !block.isEmpty && !startsNewBlock(candidate) {
                        block.append(candidate)
                        index += 1
                    } else {
                        break
                    }
                }
                out += renderList(block)
                continue
            }

            // Indented code
            if indentWidth(line) >= 4 {
                var body: [String] = []
                while index < lines.count {
                    let candidate = lines[index]
                    if candidate.trimmingCharacters(in: .whitespaces).isEmpty {
                        // Keep interior blank lines, drop trailing ones.
                        let next = lines[(index + 1)...].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        guard let next, indentWidth(next) >= 4 else { break }
                        body.append("")
                        index += 1
                        continue
                    }
                    guard indentWidth(candidate) >= 4 else { break }
                    body.append(String(candidate.dropFirst(4)))
                    index += 1
                }
                out += "<pre><code>\(escape(body.joined(separator: "\n")))</code></pre>\n"
                continue
            }

            // Paragraph, possibly closed by a setext underline
            var paragraph: [String] = []
            while index < lines.count {
                let candidate = lines[index]
                let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                if candidateTrimmed.isEmpty { break }
                if !paragraph.isEmpty, let level = setextLevel(candidateTrimmed) {
                    let text = paragraph.joined(separator: " ")
                    out += "<h\(level) id=\"\(slug(text))\">\(inline(text))</h\(level)>\n"
                    paragraph = []
                    index += 1
                    break
                }
                if !paragraph.isEmpty && startsNewBlock(candidate) { break }
                paragraph.append(candidate)
                index += 1
            }

            if !paragraph.isEmpty {
                out += "<p>\(joinParagraph(paragraph))</p>\n"
            }
        }

        return out
    }

    /// Joins the lines of a paragraph, honouring hard breaks (two trailing spaces
    /// or a trailing backslash).
    private static func joinParagraph(_ lines: [String]) -> String {
        var pieces: [String] = []
        for (offset, line) in lines.enumerated() {
            var text = line
            var hardBreak = false
            if text.hasSuffix("  ") { hardBreak = true }
            if text.hasSuffix("\\") { hardBreak = true; text = String(text.dropLast()) }
            let rendered = inline(text.trimmingCharacters(in: .whitespaces))
            let isLast = offset == lines.count - 1
            pieces.append(rendered + (hardBreak && !isLast ? "<br>" : ""))
        }
        return pieces.joined(separator: "\n")
    }

    // MARK: - Lists

    private static func renderList(_ block: [String]) -> String {
        guard let first = block.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              let marker = listMarker(first)
        else { return "" }

        let baseIndent = indentWidth(first)
        let ordered = marker.ordered
        // A list is "loose" when its items are separated by blank lines; CSS uses
        // this to decide whether items get paragraph spacing.
        var loose = false

        struct Item {
            var lines: [String]
            var task: Bool?
        }

        var items: [Item] = []
        var pendingBlank = false

        for line in block {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if !items.isEmpty { pendingBlank = true }
                continue
            }

            let indent = indentWidth(line)
            if let info = listMarker(line), indent <= baseIndent + 1 {
                if pendingBlank && !items.isEmpty { loose = true }
                pendingBlank = false

                var content = String(line.dropFirst(min(info.contentColumn, line.count)))
                var task: Bool?
                if let checked = taskBox(content) {
                    task = checked.checked
                    content = checked.rest
                }
                items.append(Item(lines: [content], task: task))
            } else if !items.isEmpty {
                if pendingBlank {
                    items[items.count - 1].lines.append("")
                    loose = true
                    pendingBlank = false
                }
                // Strip the item's own indentation so nested blocks parse cleanly.
                let strip = min(indentWidth(line), baseIndent + 2)
                items[items.count - 1].lines.append(String(line.dropFirst(strip)))
            }
        }

        guard !items.isEmpty else { return "" }

        let tag = ordered ? "ol" : "ul"
        var attributes = ""
        if ordered, let start = marker.start, start != 1 { attributes += " start=\"\(start)\"" }

        var classes: [String] = []
        if items.contains(where: { $0.task != nil }) { classes.append("task-list") }
        if loose { classes.append("loose") }
        if !classes.isEmpty { attributes += " class=\"\(classes.joined(separator: " "))\"" }

        var out = "<\(tag)\(attributes)>\n"
        for item in items {
            var inner = renderBlocks(item.lines)
            if inner.isEmpty { inner = "" }
            if let checked = item.task {
                let box = "<input type=\"checkbox\" disabled\(checked ? " checked" : "")> "
                // Put the box inside the item's first paragraph so it sits on the
                // same line as the text.
                if let range = inner.range(of: "<p>") {
                    inner = inner.replacingCharacters(in: range, with: "<p>" + box)
                } else {
                    inner = box + inner
                }
                out += "<li class=\"task\">\n\(inner)</li>\n"
            } else {
                out += "<li>\n\(inner)</li>\n"
            }
        }
        out += "</\(tag)>\n"
        return out
    }

    private static func taskBox(_ content: String) -> (checked: Bool, rest: String)? {
        let trimmed = content.drop { $0 == " " }
        guard trimmed.count >= 3 else { return nil }
        let chars = Array(trimmed)
        guard chars[0] == "[", chars[2] == "]" else { return nil }
        let inner = chars[1]
        guard inner == " " || inner == "x" || inner == "X" else { return nil }
        let rest = String(chars[3...]).drop { $0 == " " }
        return (inner != " ", String(rest))
    }

    // MARK: - Tables

    private enum Alignment: String {
        case none = ""
        case left = "left"
        case center = "center"
        case right = "right"
    }

    private static func tableAlignments(_ line: String) -> [Alignment] {
        MarkdownSyntax.splitTableRow(line.trimmingCharacters(in: .whitespaces)).map { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            let left = c.hasPrefix(":")
            let right = c.hasSuffix(":")
            switch (left, right) {
            case (true, true): return .center
            case (true, false): return .left
            case (false, true): return .right
            default: return .none
            }
        }
    }

    private static func renderTable(rows: [String], alignments: [Alignment]) -> String {
        guard let header = rows.first else { return "" }

        func cellAttribute(_ column: Int) -> String {
            guard alignments.indices.contains(column), alignments[column] != .none else { return "" }
            return " style=\"text-align:\(alignments[column].rawValue)\""
        }

        var out = "<table>\n<thead>\n<tr>"
        for (column, cell) in MarkdownSyntax.splitTableRow(header).enumerated() {
            out += "<th\(cellAttribute(column))>\(inline(cell.trimmingCharacters(in: .whitespaces)))</th>"
        }
        out += "</tr>\n</thead>\n"

        if rows.count > 1 {
            out += "<tbody>\n"
            for row in rows.dropFirst() {
                out += "<tr>"
                for (column, cell) in MarkdownSyntax.splitTableRow(row).enumerated() {
                    out += "<td\(cellAttribute(column))>\(inline(cell.trimmingCharacters(in: .whitespaces)))</td>"
                }
                out += "</tr>\n"
            }
            out += "</tbody>\n"
        }

        out += "</table>\n"
        return out
    }

    // MARK: - Inline level

    private static let allowedInlineTags: Set<String> = [
        "br", "b", "i", "em", "strong", "u", "s", "del", "ins",
        "sub", "sup", "code", "kbd", "mark", "small", "abbr", "cite", "q"
    ]

    public static func inline(_ source: String) -> String {
        var out = ""
        let chars = Array(source)
        var index = 0

        while index < chars.count {
            let character = chars[index]

            switch character {
            case "\\":
                if index + 1 < chars.count, "\\`*_{}[]()#+-.!>~=|\"".contains(chars[index + 1]) {
                    out += escape(String(chars[index + 1]))
                    index += 2
                } else {
                    out += "\\"
                    index += 1
                }

            case "`":
                if let code = scanCodeSpan(chars, from: index) {
                    out += "<code>\(escape(code.content))</code>"
                    index = code.end
                } else {
                    out += "`"
                    index += 1
                }

            case "!":
                if index + 1 < chars.count, chars[index + 1] == "[",
                   let link = scanLink(chars, from: index + 1) {
                    let title = link.title.isEmpty ? "" : " title=\"\(escapeAttribute(link.title))\""
                    out += "<img src=\"\(escapeAttribute(link.destination))\" alt=\"\(escapeAttribute(link.text))\"\(title)>"
                    index = link.end
                } else {
                    out += "!"
                    index += 1
                }

            case "[":
                if index + 1 < chars.count, chars[index + 1] == "[",
                   let wiki = scanWikiLink(chars, from: index) {
                    // Obsidian-style links have no meaning outside a vault, so they
                    // print as plain emphasised text rather than a broken link.
                    out += "<span class=\"wikilink\">\(escape(wiki.label))</span>"
                    index = wiki.end
                } else if let link = scanLink(chars, from: index) {
                    let title = link.title.isEmpty ? "" : " title=\"\(escapeAttribute(link.title))\""
                    out += "<a href=\"\(escapeAttribute(link.destination))\"\(title)>\(inline(link.text))</a>"
                    index = link.end
                } else {
                    out += "["
                    index += 1
                }

            case "*", "_", "~", "=":
                if let span = scanEmphasis(chars, from: index) {
                    out += span.open + inline(span.content) + span.close
                    index = span.end
                } else {
                    out += escape(String(character))
                    index += 1
                }

            case "<":
                if let tag = scanAngleBracket(chars, from: index) {
                    out += tag.html
                    index = tag.end
                } else {
                    out += "&lt;"
                    index += 1
                }

            case "&":
                if let entity = scanEntity(chars, from: index) {
                    out += entity.text
                    index = entity.end
                } else {
                    out += "&amp;"
                    index += 1
                }

            case ">":
                out += "&gt;"
                index += 1

            case "h":
                // Bare URLs become links; this is the common case in pasted notes.
                if let url = scanBareURL(chars, from: index) {
                    out += "<a href=\"\(escapeAttribute(url.text))\">\(escape(url.text))</a>"
                    index = url.end
                } else {
                    out.append(character)
                    index += 1
                }

            default:
                out.append(character)
                index += 1
            }
        }

        return out
    }

    private static func scanCodeSpan(_ chars: [Character], from start: Int) -> (content: String, end: Int)? {
        var fenceLength = 0
        var index = start
        while index < chars.count, chars[index] == "`" { fenceLength += 1; index += 1 }
        let contentStart = index

        while index < chars.count {
            guard chars[index] == "`" else { index += 1; continue }
            var run = index
            while run < chars.count, chars[run] == "`" { run += 1 }
            if run - index == fenceLength {
                var content = String(chars[contentStart..<index])
                // One leading and trailing space is stripping padding, per spec.
                if content.hasPrefix(" "), content.hasSuffix(" "),
                   content.contains(where: { !$0.isWhitespace }) {
                    content = String(content.dropFirst().dropLast())
                }
                return (content, run)
            }
            index = run
        }
        return nil
    }

    private static func scanLink(
        _ chars: [Character],
        from start: Int
    ) -> (text: String, destination: String, title: String, end: Int)? {
        guard start < chars.count, chars[start] == "[" else { return nil }

        var depth = 0
        var index = start
        var textEnd: Int?

        while index < chars.count {
            let character = chars[index]
            if character == "\\" { index += 2; continue }
            if character == "[" { depth += 1 }
            if character == "]" {
                depth -= 1
                if depth == 0 { textEnd = index; break }
            }
            index += 1
        }

        guard let closeBracket = textEnd, closeBracket + 1 < chars.count,
              chars[closeBracket + 1] == "("
        else { return nil }

        let text = String(chars[(start + 1)..<closeBracket])

        var cursor = closeBracket + 2
        while cursor < chars.count, chars[cursor] == " " { cursor += 1 }

        var destination = ""
        if cursor < chars.count, chars[cursor] == "<" {
            cursor += 1
            while cursor < chars.count, chars[cursor] != ">" {
                destination.append(chars[cursor])
                cursor += 1
            }
            cursor += 1
        } else {
            var parens = 0
            while cursor < chars.count {
                let character = chars[cursor]
                if character == " " || character == "\t" { break }
                if character == "(" { parens += 1 }
                if character == ")" {
                    if parens == 0 { break }
                    parens -= 1
                }
                destination.append(character)
                cursor += 1
            }
        }

        while cursor < chars.count, chars[cursor] == " " { cursor += 1 }

        var title = ""
        if cursor < chars.count, chars[cursor] == "\"" || chars[cursor] == "'" {
            let quote = chars[cursor]
            cursor += 1
            while cursor < chars.count, chars[cursor] != quote {
                title.append(chars[cursor])
                cursor += 1
            }
            cursor += 1
        }

        while cursor < chars.count, chars[cursor] == " " { cursor += 1 }
        guard cursor < chars.count, chars[cursor] == ")" else { return nil }

        return (text, destination, title, cursor + 1)
    }

    private static func scanWikiLink(_ chars: [Character], from start: Int) -> (label: String, end: Int)? {
        guard start + 1 < chars.count, chars[start] == "[", chars[start + 1] == "[" else { return nil }
        var index = start + 2
        var body = ""
        while index + 1 < chars.count {
            if chars[index] == "]" && chars[index + 1] == "]" {
                // `[[Note|Alias]]` displays the alias.
                let label = body.components(separatedBy: "|").last ?? body
                return (label, index + 2)
            }
            body.append(chars[index])
            index += 1
        }
        return nil
    }

    private static func scanEmphasis(
        _ chars: [Character],
        from start: Int
    ) -> (open: String, close: String, content: String, end: Int)? {
        let delimiter = chars[start]

        var runLength = 0
        var index = start
        while index < chars.count, chars[index] == delimiter { runLength += 1; index += 1 }

        if delimiter == "~" || delimiter == "=" {
            guard runLength >= 2 else { return nil }
            runLength = 2
        } else {
            runLength = min(runLength, 3)
        }

        let contentStart = start + runLength
        guard contentStart < chars.count, !chars[contentStart].isWhitespace else { return nil }

        // `snake_case_words` should not turn into emphasis.
        if delimiter == "_", start > 0, chars[start - 1].isLetter || chars[start - 1].isNumber { return nil }

        var cursor = contentStart
        while cursor < chars.count {
            if chars[cursor] == "`" {
                if let code = scanCodeSpan(chars, from: cursor) { cursor = code.end; continue }
                cursor += 1
                continue
            }
            if chars[cursor] == "\\" { cursor += 2; continue }

            guard chars[cursor] == delimiter else { cursor += 1; continue }

            var runEnd = cursor
            while runEnd < chars.count, chars[runEnd] == delimiter { runEnd += 1 }
            let closingLength = runEnd - cursor

            if closingLength >= runLength, cursor > contentStart, !chars[cursor - 1].isWhitespace {
                if delimiter == "_", runEnd < chars.count,
                   chars[runEnd].isLetter || chars[runEnd].isNumber {
                    cursor = runEnd
                    continue
                }
                let content = String(chars[contentStart..<cursor])
                let tags = emphasisTags(delimiter: delimiter, length: runLength)
                return (tags.open, tags.close, content, cursor + runLength)
            }
            cursor = runEnd
        }
        return nil
    }

    private static func emphasisTags(delimiter: Character, length: Int) -> (open: String, close: String) {
        switch delimiter {
        case "~": return ("<del>", "</del>")
        case "=": return ("<mark>", "</mark>")
        default:
            switch length {
            case 1: return ("<em>", "</em>")
            case 2: return ("<strong>", "</strong>")
            default: return ("<strong><em>", "</em></strong>")
            }
        }
    }

    private static func scanAngleBracket(_ chars: [Character], from start: Int) -> (html: String, end: Int)? {
        var index = start + 1
        var body = ""
        while index < chars.count, chars[index] != ">", chars[index] != "<" {
            body.append(chars[index])
            index += 1
        }
        guard index < chars.count, chars[index] == ">" else { return nil }
        let end = index + 1

        // Autolink
        if body.contains(":"), !body.contains(" ") {
            let label = body.hasPrefix("mailto:") ? String(body.dropFirst(7)) : body
            return ("<a href=\"\(escapeAttribute(body))\">\(escape(label))</a>", end)
        }

        // Whitelisted inline HTML
        var name = body
        if name.hasPrefix("/") { name.removeFirst() }
        if name.hasSuffix("/") { name.removeLast() }
        let tagName = name.components(separatedBy: CharacterSet(charactersIn: " \t")).first?.lowercased() ?? ""
        if allowedInlineTags.contains(tagName) {
            // Re-emit without any attributes: no styles, no handlers, no sources.
            let closing = body.hasPrefix("/") ? "/" : ""
            return ("<\(closing)\(tagName)>", end)
        }

        return nil
    }

    private static func scanEntity(_ chars: [Character], from start: Int) -> (text: String, end: Int)? {
        var index = start + 1
        var body = ""
        while index < chars.count, body.count < 10, chars[index] != ";" {
            let character = chars[index]
            guard character.isLetter || character.isNumber || character == "#" else { return nil }
            body.append(character)
            index += 1
        }
        guard index < chars.count, chars[index] == ";", !body.isEmpty else { return nil }
        return ("&\(body);", index + 1)
    }

    private static func scanBareURL(_ chars: [Character], from start: Int) -> (text: String, end: Int)? {
        // Compare in place: materialising the rest of the document at every "h"
        // would make this quadratic.
        func matches(_ prefix: String) -> Bool {
            let needle = Array(prefix)
            guard start + needle.count <= chars.count else { return false }
            for (offset, character) in needle.enumerated() where chars[start + offset] != character {
                return false
            }
            return true
        }
        guard matches("http://") || matches("https://") else { return nil }
        if start > 0 {
            let previous = chars[start - 1]
            if previous == "(" || previous == "\"" || previous == "'" || previous == "<" { return nil }
        }
        var index = start
        while index < chars.count {
            let character = chars[index]
            if character.isWhitespace || character == "<" || character == ">" { break }
            index += 1
        }
        // Trailing punctuation usually belongs to the sentence, not the URL.
        while index > start, ".,;:!?)".contains(chars[index - 1]) {
            index -= 1
        }
        guard index > start + 8 else { return nil }
        return (String(chars[start..<index]), index)
    }

    // MARK: - Shared line helpers

    private static func indentWidth(_ line: String) -> Int {
        var width = 0
        for character in line {
            if character == " " { width += 1 }
            else if character == "\t" { width += 4 }
            else { break }
        }
        return width
    }

    private static func fenceInfo(_ trimmed: String) -> (character: Character, length: Int, info: String)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        var length = 0
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index] == first {
            length += 1
            index = trimmed.index(after: index)
        }
        guard length >= 3 else { return nil }
        let info = String(trimmed[index...]).trimmingCharacters(in: .whitespaces)
        if first == "`", info.contains("`") { return nil }
        return (first, length, info)
    }

    private static func atxHeading(_ trimmed: String) -> (level: Int, text: String)? {
        var level = 0
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index] == "#" {
            level += 1
            index = trimmed.index(after: index)
        }
        guard (1...6).contains(level) else { return nil }
        if index == trimmed.endIndex { return (level, "") }
        guard trimmed[index] == " " else { return nil }

        var text = String(trimmed[index...]).trimmingCharacters(in: .whitespaces)
        // Closing hashes are decoration: "## Title ##".
        while text.hasSuffix("#") { text.removeLast() }
        return (level, text.trimmingCharacters(in: .whitespaces))
    }

    private static func setextLevel(_ trimmed: String) -> Int? {
        guard !trimmed.isEmpty else { return nil }
        if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if trimmed.count >= 2, trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let stripped = trimmed.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3, let first = stripped.first,
              first == "-" || first == "*" || first == "_"
        else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    private static func isBlockquote(_ line: String) -> Bool {
        indentWidth(line) <= 3 && line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    private static func stripQuoteMarker(_ line: String) -> String {
        var body = Substring(line).drop { $0 == " " || $0 == "\t" }
        if body.hasPrefix(">") { body = body.dropFirst() }
        if body.hasPrefix(" ") { body = body.dropFirst() }
        return String(body)
    }

    private static func startsNewBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if fenceInfo(trimmed) != nil { return true }
        if atxHeading(trimmed) != nil { return true }
        if isHorizontalRule(trimmed) { return true }
        if isBlockquote(line) { return true }

        // A list interrupts a paragraph — except a numbered one that doesn't
        // start at 1, so "the year\n1999. It rained" stays a sentence.
        if let marker = listMarker(line) {
            return !marker.ordered || marker.start == 1
        }
        return false
    }

    private struct ListMarkerInfo {
        var ordered: Bool
        var start: Int?
        /// Character offset in the original line where the item's content begins.
        var contentColumn: Int
    }

    private static func listMarker(_ line: String) -> ListMarkerInfo? {
        let chars = Array(line)
        var index = 0
        while index < chars.count, chars[index] == " " || chars[index] == "\t" { index += 1 }
        guard index < chars.count else { return nil }

        var ordered = false
        var number: Int?

        if chars[index] == "-" || chars[index] == "*" || chars[index] == "+" {
            index += 1
        } else if chars[index].isNumber {
            var digits = ""
            while index < chars.count, chars[index].isNumber, digits.count < 9 {
                digits.append(chars[index])
                index += 1
            }
            guard index < chars.count, chars[index] == "." || chars[index] == ")" else { return nil }
            index += 1
            ordered = true
            number = Int(digits)
        } else {
            return nil
        }

        guard index < chars.count else {
            return ListMarkerInfo(ordered: ordered, start: number, contentColumn: index)
        }
        guard chars[index] == " " || chars[index] == "\t" else { return nil }
        while index < chars.count, chars[index] == " " || chars[index] == "\t" { index += 1 }
        return ListMarkerInfo(ordered: ordered, start: number, contentColumn: index)
    }

    // MARK: - Escaping

    public static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(character)
            }
        }
        return out
    }

    public static func escapeAttribute(_ text: String) -> String {
        escape(text)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func slug(_ text: String) -> String {
        let lowered = text.lowercased()
        var out = ""
        for character in lowered {
            if character.isLetter || character.isNumber { out.append(character) }
            else if character == " " || character == "-" || character == "_" { out.append("-") }
        }
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
