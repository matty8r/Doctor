import AppKit

/// The formatting commands behind the Format menu. All of them go through
/// `shouldChangeText` so undo works the way it does everywhere else on the Mac.
enum MarkdownEditing {

    // MARK: - Inline wrapping

    /// Wraps the selection in `token`, or unwraps it if it's already wrapped.
    /// With no selection, wraps the word under the caret; failing that, inserts
    /// the pair and puts the caret between them.
    static func toggleWrap(_ textView: NSTextView, with token: String) {
        let text = textView.string as NSString
        var selection = textView.selectedRange()
        let tokenLength = (token as NSString).length

        if selection.length == 0 {
            selection = wordRange(in: text, around: selection.location)
        }

        // Already wrapped, inside the selection?
        if selection.length >= tokenLength * 2 {
            let body = text.substring(with: selection)
            if body.hasPrefix(token) && body.hasSuffix(token) {
                let stripped = String(body.dropFirst(token.count).dropLast(token.count))
                replace(textView, range: selection, with: stripped,
                        select: NSRange(location: selection.location, length: (stripped as NSString).length))
                return
            }
        }

        // Already wrapped, just outside the selection?
        let outer = NSRange(location: selection.location - tokenLength,
                            length: selection.length + tokenLength * 2)
        if outer.location >= 0, NSMaxRange(outer) <= text.length {
            let body = text.substring(with: outer)
            if body.hasPrefix(token) && body.hasSuffix(token) {
                let stripped = text.substring(with: selection)
                replace(textView, range: outer, with: stripped,
                        select: NSRange(location: outer.location, length: (stripped as NSString).length))
                return
            }
        }

        let body = text.substring(with: selection)
        let wrapped = token + body + token
        replace(textView, range: selection, with: wrapped,
                select: NSRange(location: selection.location + tokenLength, length: (body as NSString).length))
    }

    /// Wraps the selection as a link. If the clipboard holds a URL, it's used as
    /// the destination — which is the common case when you've just copied one.
    static func insertLink(_ textView: NSTextView) {
        let text = textView.string as NSString
        var selection = textView.selectedRange()
        if selection.length == 0 {
            selection = wordRange(in: text, around: selection.location)
        }

        let label = text.substring(with: selection)
        let pasted = NSPasteboard.general.string(forType: .string) ?? ""
        let looksLikeURL = pasted.hasPrefix("http://") || pasted.hasPrefix("https://")
            || pasted.hasPrefix("mailto:") || pasted.hasPrefix("obsidian://")
        let destination = looksLikeURL ? pasted : ""

        let replacement = "[\(label)](\(destination))"
        let caret: NSRange
        if label.isEmpty {
            caret = NSRange(location: selection.location + 1, length: 0)
        } else if destination.isEmpty {
            caret = NSRange(location: selection.location + (label as NSString).length + 3, length: 0)
        } else {
            caret = NSRange(location: selection.location + (replacement as NSString).length, length: 0)
        }
        replace(textView, range: selection, with: replacement, select: caret)
    }

    static func insertCodeBlock(_ textView: NSTextView) {
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        let body = text.substring(with: selection)
        let needsLeadingNewline = selection.location > 0
            && text.substring(with: NSRange(location: selection.location - 1, length: 1)) != "\n"

        let replacement = (needsLeadingNewline ? "\n" : "") + "```\n" + body + (body.hasSuffix("\n") ? "" : "\n") + "```\n"
        let caretOffset = (needsLeadingNewline ? 1 : 0) + 3
        replace(textView, range: selection, with: replacement,
                select: NSRange(location: selection.location + caretOffset, length: 0))
    }

    // MARK: - Line prefixes

    /// Sets, or clears, the heading level of every line in the selection.
    static func setHeading(_ textView: NSTextView, level: Int) {
        transformLines(textView) { line in
            var body = Substring(line)
            // Drop any existing heading marker first.
            let stripped = body.drop { $0 == "#" }
            if stripped.count != body.count {
                body = stripped.hasPrefix(" ") ? stripped.dropFirst() : stripped
            }
            guard level > 0 else { return String(body) }
            return String(repeating: "#", count: level) + " " + String(body)
        }
    }

    static func toggleBlockquote(_ textView: NSTextView) {
        let lines = selectedLines(textView)
        let allQuoted = lines.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }
            && !lines.isEmpty

        transformLines(textView) { line in
            if allQuoted {
                var body = Substring(line).drop { $0 == " " }
                if body.hasPrefix(">") { body = body.dropFirst() }
                if body.hasPrefix(" ") { body = body.dropFirst() }
                return String(body)
            }
            return line.trimmingCharacters(in: .whitespaces).isEmpty ? line : "> " + line
        }
    }

    static func toggleBulletList(_ textView: NSTextView) {
        toggleListPrefix(textView) { _ in "- " }
    }

    static func toggleNumberedList(_ textView: NSTextView) {
        var counter = 0
        toggleListPrefix(textView) { _ in
            counter += 1
            return "\(counter). "
        }
    }

    static func toggleTaskList(_ textView: NSTextView) {
        toggleListPrefix(textView) { _ in "- [ ] " }
    }

    private static func toggleListPrefix(_ textView: NSTextView, prefix: @escaping (Int) -> String) {
        let lines = selectedLines(textView)
        let markers = ["- [ ] ", "- [x] ", "- ", "* ", "+ "]

        func stripped(_ line: String) -> String? {
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            let body = line.dropFirst(indent.count)
            for marker in markers where body.hasPrefix(marker) {
                return String(indent) + String(body.dropFirst(marker.count))
            }
            // Ordered items: "12. text"
            let digits = body.prefix { $0.isNumber }
            if !digits.isEmpty {
                let rest = body.dropFirst(digits.count)
                if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                    return String(indent) + String(rest.dropFirst(2))
                }
            }
            return nil
        }

        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allListed = !nonEmpty.isEmpty && nonEmpty.allSatisfy { stripped($0) != nil }

        var index = 0
        transformLines(textView) { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            if allListed { return stripped(line) ?? line }
            let base = stripped(line) ?? line
            let indent = base.prefix { $0 == " " || $0 == "\t" }
            let body = base.dropFirst(indent.count)
            index += 1
            return String(indent) + prefix(index) + String(body)
        }
    }

    /// Indents or outdents the selected lines by one list step.
    static func shiftIndent(in textView: NSTextView, by steps: Int) {
        let unit = "    "
        transformLines(textView) { line in
            if steps > 0 { return unit + line }
            if line.hasPrefix(unit) { return String(line.dropFirst(unit.count)) }
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            return String(line.drop { $0 == " " })
        }
    }

    // MARK: - Snippets

    /// Wraps the selection as `prefix…suffix`; with nothing selected, inserts
    /// the placeholder between them and selects it, ready to be typed over.
    static func insertInline(_ textView: NSTextView, prefix: String, placeholder: String, suffix: String) {
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        let body = selection.length > 0 ? text.substring(with: selection) : placeholder
        let offset = (prefix as NSString).length
        replace(textView, range: selection, with: prefix + body + suffix,
                select: NSRange(location: selection.location + offset, length: (body as NSString).length))
    }

    /// Inserts a block on lines of its own, with blank lines around it, and
    /// selects `select` inside it (the whole block when that's nil).
    static func insertBlock(_ textView: NSTextView, _ block: String, select: String? = nil) {
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        let before = text.substring(to: selection.location)
        let after = text.substring(from: NSMaxRange(selection))

        let lead = before.isEmpty || before.hasSuffix("\n\n") ? "" : (before.hasSuffix("\n") ? "\n" : "\n\n")
        let trail = after.hasPrefix("\n") ? "\n" : "\n\n"
        let replacement = lead + block + trail

        let blockStart = selection.location + (lead as NSString).length
        var target = NSRange(location: blockStart, length: (block as NSString).length)
        if let select {
            let inner = (block as NSString).range(of: select)
            if inner.location != NSNotFound {
                target = NSRange(location: blockStart + inner.location, length: inner.length)
            }
        }
        replace(textView, range: selection, with: replacement, select: target)
    }

    // MARK: - Machinery

    private static func selectedLineRange(_ textView: NSTextView) -> NSRange {
        let text = textView.string as NSString
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        let selection = textView.selectedRange()
        return text.lineRange(for: selection)
    }

    private static func selectedLines(_ textView: NSTextView) -> [String] {
        let text = textView.string as NSString
        let range = selectedLineRange(textView)
        guard range.length > 0 else { return [""] }
        var block = text.substring(with: range)
        let hadTrailingNewline = block.hasSuffix("\n")
        if hadTrailingNewline { block.removeLast() }
        return block.components(separatedBy: "\n")
    }

    private static func transformLines(_ textView: NSTextView, _ transform: (String) -> String) {
        let text = textView.string as NSString
        let range = selectedLineRange(textView)
        guard range.length > 0 || text.length == 0 else { return }

        var block = range.length > 0 ? text.substring(with: range) : ""
        let hadTrailingNewline = block.hasSuffix("\n")
        if hadTrailingNewline { block.removeLast() }

        let transformed = block
            .components(separatedBy: "\n")
            .map(transform)
            .joined(separator: "\n") + (hadTrailingNewline ? "\n" : "")

        let newLength = (transformed as NSString).length
        replace(textView, range: range, with: transformed,
                select: NSRange(location: range.location, length: newLength))
    }

    private static func replace(_ textView: NSTextView, range: NSRange, with string: String, select: NSRange) {
        guard textView.shouldChangeText(in: range, replacementString: string) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: string)
        textView.didChangeText()

        let length = (textView.string as NSString).length
        let clamped = NSRange(
            location: min(select.location, length),
            length: min(select.length, max(0, length - min(select.location, length)))
        )
        textView.setSelectedRange(clamped)
    }

    /// The word under `location`, used when a formatting command is invoked with
    /// no selection — wrapping the word you're standing on is almost always the
    /// intent.
    private static func wordRange(in text: NSString, around location: Int) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        let breaks = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "*_`~[](){}<>\"',;:!?"))

        var start = min(location, text.length)
        while start > 0 {
            let scalar = text.substring(with: NSRange(location: start - 1, length: 1)).unicodeScalars.first
            guard let scalar, !breaks.contains(scalar) else { break }
            start -= 1
        }

        var end = min(location, text.length)
        while end < text.length {
            let scalar = text.substring(with: NSRange(location: end, length: 1)).unicodeScalars.first
            guard let scalar, !breaks.contains(scalar) else { break }
            end += 1
        }

        return NSRange(location: start, length: end - start)
    }
}
