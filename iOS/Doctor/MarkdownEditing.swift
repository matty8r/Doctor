import Foundation

/// What the keyboard toolbar can do to the text. Adapted from Sprig's
/// `ios/Sprig/Model/MarkdownEditing.swift` in `obsidianWeb` — same pure
/// (text, selection) → (text, selection) shape, same UTF-16 `NSRange`
/// reasoning (UITextView counts that way; converting at the edges rather
/// than working in `NSRange` throughout mis-places the cursor the first
/// time anyone types an emoji).
///
/// The command set itself isn't a straight copy: it matches what
/// `DoctorMarkdown` actually renders, from the same list the Mac app's
/// `CheatSheetView` draws from. `.highlight` and `.task` exist here because
/// Doctor's renderer understands `==text==` and `- [ ] `; Sprig's `.callout`
/// doesn't appear here because Doctor's renderer has no special handling for
/// `> [!note]` — it would just render as a quote with literal bracket text.
enum MarkdownCommand: String, CaseIterable, Identifiable {
    case bold, italic, strikethrough, highlight, inlineCode, link
    case heading1, heading2, heading3
    case bullet, numbered, task, quote, codeBlock, rule

    var id: String { rawValue }

    /// Headings are drawn as text rather than a glyph: the three
    /// `textformat.size` symbols are near-identical A shapes at toolbar size.
    var textLabel: String? {
        switch self {
        case .heading1: return "H1"
        case .heading2: return "H2"
        case .heading3: return "H3"
        default: return nil
        }
    }

    var symbol: String {
        switch self {
        case .bold: return "bold"
        case .italic: return "italic"
        case .strikethrough: return "strikethrough"
        case .highlight: return "highlighter"
        case .inlineCode: return "chevron.left.forwardslash.chevron.right"
        case .link: return "link"
        case .heading1, .heading2, .heading3: return "textformat.size"
        case .bullet: return "list.bullet"
        case .numbered: return "list.number"
        case .task: return "checklist"
        case .quote: return "text.quote"
        case .codeBlock: return "curlybraces.square"
        case .rule: return "minus"
        }
    }

    var label: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .strikethrough: return "Strikethrough"
        case .highlight: return "Highlight"
        case .inlineCode: return "Code"
        case .link: return "Link"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .bullet: return "Bulleted List"
        case .numbered: return "Numbered List"
        case .task: return "Task"
        case .quote: return "Quote"
        case .codeBlock: return "Code Block"
        case .rule: return "Divider"
        }
    }

    /// Inline commands act on the selection; section commands act on whole
    /// lines. The toolbar groups them with a separator on this boundary.
    var isInline: Bool {
        switch self {
        case .bold, .italic, .strikethrough, .highlight, .inlineCode, .link: return true
        default: return false
        }
    }
}

/// Applying Markdown syntax to a text selection. Pure functions over
/// (text, selection) so behaviour is testable without a running app.
enum MarkdownEditing {

    struct Result: Equatable {
        var text: String
        var selection: NSRange
    }

    static func apply(_ command: MarkdownCommand, to text: String, selection: NSRange) -> Result {
        switch command {
        case .bold: return wrap("**", text, selection)
        case .italic: return wrap("*", text, selection)
        case .strikethrough: return wrap("~~", text, selection)
        case .highlight: return wrap("==", text, selection)
        case .inlineCode: return wrap("`", text, selection)
        case .link: return makeLink(text, selection)

        case .heading1: return heading(1, text, selection)
        case .heading2: return heading(2, text, selection)
        case .heading3: return heading(3, text, selection)

        case .bullet: return prefixLines("- ", text, selection)
        case .quote: return prefixLines("> ", text, selection)
        case .numbered: return numberLines(text, selection)
        case .task: return taskLines(text, selection)
        case .codeBlock: return codeFence(text, selection)
        case .rule: return insertBlock("---", text, selection)
        }
    }

    // MARK: - Inline

    private static func wrap(_ marker: String, _ text: String, _ selection: NSRange) -> Result {
        let ns = text as NSString
        let markerLength = (marker as NSString).length
        let end = selection.location + selection.length

        // Toggle off when the selection is already wrapped in this marker.
        let before = selection.location - markerLength
        if before >= 0, end + markerLength <= ns.length,
           ns.substring(with: NSRange(location: before, length: markerLength)) == marker,
           ns.substring(with: NSRange(location: end, length: markerLength)) == marker {
            let out = NSMutableString(string: text)
            out.deleteCharacters(in: NSRange(location: end, length: markerLength))
            out.deleteCharacters(in: NSRange(location: before, length: markerLength))
            return Result(
                text: out as String,
                selection: NSRange(location: before, length: selection.length)
            )
        }

        let out = NSMutableString(string: text)
        out.insert(marker, at: end)
        out.insert(marker, at: selection.location)
        // With no selection the cursor lands between the markers, ready to type.
        return Result(
            text: out as String,
            selection: NSRange(location: selection.location + markerLength, length: selection.length)
        )
    }

    private static func makeLink(_ text: String, _ selection: NSRange) -> Result {
        let ns = text as NSString
        let selected = ns.substring(with: selection)
        let replacement = "[\(selected)](url)"
        let out = NSMutableString(string: text)
        out.replaceCharacters(in: selection, with: replacement)

        // Select the placeholder so typing the address replaces it.
        let urlOffset = selection.location + (selected as NSString).length + 3
        return Result(text: out as String, selection: NSRange(location: urlOffset, length: 3))
    }

    // MARK: - Sections

    /// The lines the selection touches, plus that region's range.
    private static func lineBlock(_ text: String, _ selection: NSRange) -> (range: NSRange, lines: [String], trailingNewline: Bool) {
        let ns = text as NSString
        let safe = NSRange(
            location: min(selection.location, ns.length),
            length: min(selection.length, max(0, ns.length - min(selection.location, ns.length)))
        )
        let range = ns.lineRange(for: safe)
        var lines = ns.substring(with: range).components(separatedBy: "\n")
        var trailing = false
        if lines.count > 1, lines.last == "" {
            lines.removeLast()
            trailing = true
        }
        return (range, lines, trailing)
    }

    private static func replace(_ text: String, _ range: NSRange, _ lines: [String], _ trailing: Bool) -> Result {
        var joined = lines.joined(separator: "\n")
        if trailing { joined += "\n" }
        let out = NSMutableString(string: text)
        out.replaceCharacters(in: range, with: joined)
        return Result(
            text: out as String,
            selection: NSRange(location: range.location, length: (joined as NSString).length)
        )
    }

    private static func prefixLines(_ prefix: String, _ text: String, _ selection: NSRange) -> Result {
        let (range, lines, trailing) = lineBlock(text, selection)
        let meaningful = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // Toggle off only when every line already carries the prefix, so a
        // partly-formatted selection completes rather than clears.
        let allPrefixed = !meaningful.isEmpty && meaningful.allSatisfy { $0.hasPrefix(prefix) }

        let updated = lines.map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            if allPrefixed { return String(line.dropFirst(prefix.count)) }
            return line.hasPrefix(prefix) ? line : prefix + line
        }
        return replace(text, range, updated, trailing)
    }

    private static let numberedPrefix = try? NSRegularExpression(pattern: #"^\d+\.\s"#)

    private static func numberLines(_ text: String, _ selection: NSRange) -> Result {
        let (range, lines, trailing) = lineBlock(text, selection)

        func numberedLength(_ line: String) -> Int? {
            guard let regex = numberedPrefix else { return nil }
            let ns = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
            else { return nil }
            return match.range.length
        }

        let meaningful = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allNumbered = !meaningful.isEmpty && meaningful.allSatisfy { numberedLength($0) != nil }

        var counter = 0
        let updated = lines.map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            if allNumbered {
                let length = numberedLength(line) ?? 0
                return String((line as NSString).substring(from: length))
            }
            counter += 1
            // Renumber from one rather than trusting what is there, so an
            // out-of-order selection comes out sequential.
            let stripped = numberedLength(line).map { (line as NSString).substring(from: $0) } ?? line
            return "\(counter). \(stripped)"
        }
        return replace(text, range, updated, trailing)
    }

    /// Either checkbox state counts as "already a task", so toggling off
    /// a checked item removes it rather than leaving a bare `[x] ` behind.
    private static func taskLines(_ text: String, _ selection: NSRange) -> Result {
        let (range, lines, trailing) = lineBlock(text, selection)
        let unchecked = "- [ ] "
        let checked = "- [x] "

        func taskPrefixLength(_ line: String) -> Int? {
            if line.hasPrefix(unchecked) { return unchecked.count }
            if line.hasPrefix(checked) { return checked.count }
            return nil
        }

        let meaningful = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allTasks = !meaningful.isEmpty && meaningful.allSatisfy { taskPrefixLength($0) != nil }

        let updated = lines.map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            if allTasks {
                let length = taskPrefixLength(line) ?? 0
                return String((line as NSString).substring(from: length))
            }
            return taskPrefixLength(line) != nil ? line : unchecked + line
        }
        return replace(text, range, updated, trailing)
    }

    private static let headingPrefix = try? NSRegularExpression(pattern: #"^#{1,6}\s"#)

    private static func heading(_ level: Int, _ text: String, _ selection: NSRange) -> Result {
        let (range, lines, trailing) = lineBlock(text, selection)
        let marker = String(repeating: "#", count: level) + " "

        let updated = lines.map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }

            var bare = line
            if let regex = headingPrefix {
                let ns = line as NSString
                if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                    bare = ns.substring(from: match.range.length)
                }
            }
            // Tapping the level a line already is removes it, rather than
            // stacking a second run of hashes.
            return line.hasPrefix(marker) ? bare : marker + bare
        }
        return replace(text, range, updated, trailing)
    }

    private static func codeFence(_ text: String, _ selection: NSRange) -> Result {
        let (range, lines, trailing) = lineBlock(text, selection)
        let updated = ["```"] + lines + ["```"]
        let result = replace(text, range, updated, trailing)
        // Land the cursor inside the fence when there was nothing to wrap.
        if lines.joined().trimmingCharacters(in: .whitespaces).isEmpty {
            return Result(text: result.text, selection: NSRange(location: range.location + 4, length: 0))
        }
        return result
    }

    private static func insertBlock(_ block: String, _ text: String, _ selection: NSRange) -> Result {
        let ns = text as NSString
        let lineStart = ns.lineRange(for: NSRange(location: min(selection.location, ns.length), length: 0))
        let insertAt = lineStart.location + lineStart.length

        var insertion = block + "\n"
        if insertAt > 0, ns.substring(with: NSRange(location: insertAt - 1, length: 1)) != "\n" {
            insertion = "\n" + insertion
        }

        let out = NSMutableString(string: text)
        out.insert(insertion, at: insertAt)
        return Result(
            text: out as String,
            selection: NSRange(location: insertAt + (insertion as NSString).length, length: 0)
        )
    }
}
