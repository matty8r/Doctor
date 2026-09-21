import AppKit
import DoctorMarkdown

/// The text view itself. Everything here is about making a plain `NSTextView`
/// behave like a Markdown editor: plain-text paste, list continuation,
/// Cmd-click to follow links, click to tick a checkbox.
final class EditorTextView: NSTextView {

    var mode: EditorMode = .preview
    var settings: AppSettings = .shared
    /// Called when the view wants the document re-highlighted out of band.
    var onStructuralEdit: (() -> Void)?

    // MARK: - Paste

    override func paste(_ sender: Any?) {
        // Styled text has no business in a Markdown file.
        pasteAsPlainText(sender)
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == .rtf || type == .rtfd || type == .html {
            if let plain = pboard.string(forType: .string) {
                insertText(plain, replacementRange: selectedRange())
                return true
            }
        }
        return super.readSelection(from: pboard, type: type)
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.string]
    }

    // MARK: - Dropping files

    /// Dropping a file on the editor opens it as a tab rather than pasting its path.
    var onOpenFiles: (([URL]) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFileURLs(from: sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFileURLs(from: sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedFileURLs(from: sender)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        onOpenFiles?(urls)
        return true
    }

    private func droppedFileURLs(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls ?? []
    }

    // MARK: - Return: continue the list you're in

    override func insertNewline(_ sender: Any?) {
        guard settings.smartLists, selectedRanges.count == 1 else {
            super.insertNewline(sender)
            return
        }

        let text = string as NSString
        let selection = selectedRange()
        let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let line = text.substring(with: lineRange).replacingOccurrences(of: "\n", with: "")

        guard let continuation = ListContinuation(line: line) else {
            super.insertNewline(sender)
            return
        }

        // Pressing Return on an empty item ends the list. The marker is removed
        // and the caret stays put, rather than adding another empty line.
        if continuation.isEmptyItem {
            let clearRange = NSRange(location: lineRange.location,
                                     length: min(line.utf16.count, text.length - lineRange.location))
            if shouldChangeText(in: clearRange, replacementString: "") {
                textStorage?.replaceCharacters(in: clearRange, with: "")
                didChangeText()
                setSelectedRange(NSRange(location: lineRange.location, length: 0))
            }
            return
        }

        let insertion = "\n" + continuation.nextPrefix
        if shouldChangeText(in: selection, replacementString: insertion) {
            textStorage?.replaceCharacters(in: selection, with: insertion)
            didChangeText()
            setSelectedRange(NSRange(location: selection.location + (insertion as NSString).length, length: 0))
        }
    }

    // MARK: - Tab: indent list items, otherwise insert spaces

    override func insertTab(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length > 0 {
            MarkdownEditing.shiftIndent(in: self, by: 1)
            return
        }

        let text = string as NSString
        let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let line = text.substring(with: lineRange)
        let beforeCaret = selection.location - lineRange.location

        // Tab at the front of a list item nests it; anywhere else it's just a tab.
        if ListContinuation(line: line.replacingOccurrences(of: "\n", with: "")) != nil,
           beforeCaret <= leadingWhitespaceLength(of: line) + 2 {
            MarkdownEditing.shiftIndent(in: self, by: 1)
            return
        }

        insertText("    ", replacementRange: selection)
    }

    override func insertBacktab(_ sender: Any?) {
        MarkdownEditing.shiftIndent(in: self, by: -1)
    }

    private func leadingWhitespaceLength(of line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    // MARK: - Clicking

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)

        if event.modifierFlags.contains(.command) {
            if let url = linkURL(at: index) {
                NSWorkspace.shared.open(url)
                return
            }
        }

        if event.clickCount == 1, !event.modifierFlags.contains(.shift), toggleTaskBox(at: index) {
            return
        }

        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        // No per-link cursor rects: recomputing them on every edit costs more
        // than it's worth, and Cmd-click is discoverable from the menu.
    }

    /// Resolves the Markdown link under a character index, if there is one.
    func linkURL(at index: Int) -> URL? {
        let text = string as NSString
        guard index >= 0, index <= text.length, text.length > 0 else { return nil }

        let lineRange = text.lineRange(for: NSRange(location: min(index, max(0, text.length - 1)), length: 0))
        let spans = MarkdownSyntax.inlineTokens(in: text, range: lineRange)

        for span in spans where NSLocationInRange(index, span.range) {
            switch span.kind {
            case .link, .image:
                guard let destination = span.destination else { return nil }
                return resolve(text.substring(with: destination).trimmingCharacters(in: .whitespaces))
            case .autolink, .bareURL:
                return resolve(text.substring(with: span.content))
            default:
                continue
            }
        }
        return nil
    }

    private func resolve(_ raw: String) -> URL? {
        var candidate = raw.trimmingCharacters(in: .whitespaces)
        if candidate.hasPrefix("<") && candidate.hasSuffix(">") {
            candidate = String(candidate.dropFirst().dropLast())
        }
        guard !candidate.isEmpty else { return nil }

        if candidate.contains("://") || candidate.hasPrefix("mailto:") || candidate.hasPrefix("obsidian:") {
            return URL(string: candidate)
        }
        if candidate.hasPrefix("#") { return nil }

        // Relative path: resolve against the document's own folder.
        if let base = documentDirectory {
            let resolved = URL(fileURLWithPath: candidate, relativeTo: base).standardizedFileURL
            if FileManager.default.fileExists(atPath: resolved.path) { return resolved }
        }
        return URL(string: candidate)
    }

    /// Clicking directly on `[ ]` or `[x]` ticks it. Returns true if handled.
    private func toggleTaskBox(at index: Int) -> Bool {
        let text = string as NSString
        guard index >= 0, index < text.length else { return false }

        let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
        let line = text.substring(with: lineRange) as NSString

        // Search in UTF-16 space; a character offset would be wrong the moment
        // the line contains an emoji.
        var found = line.range(of: "[ ]")
        if found.location == NSNotFound { found = line.range(of: "[x]") }
        if found.location == NSNotFound { found = line.range(of: "[X]") }
        guard found.location != NSNotFound else { return false }

        let start = lineRange.location + found.location
        let boxRange = NSRange(location: start, length: 3)
        guard NSLocationInRange(index, boxRange) else { return false }

        // Only the marker at the head of a list item counts.
        let prefix = text.substring(with: NSRange(location: lineRange.location, length: start - lineRange.location))
        let prefixTrimmed = prefix.trimmingCharacters(in: .whitespaces)
        guard prefixTrimmed == "-" || prefixTrimmed == "*" || prefixTrimmed == "+"
                || prefixTrimmed.hasSuffix(".") || prefixTrimmed.hasSuffix(")")
        else { return false }

        let current = text.substring(with: boxRange)
        let replacement = current == "[ ]" ? "[x]" : "[ ]"

        if shouldChangeText(in: boxRange, replacementString: replacement) {
            textStorage?.replaceCharacters(in: boxRange, with: replacement)
            didChangeText()
        }
        return true
    }

    // MARK: - Document context

    /// The folder the current document lives in, for resolving relative links.
    var documentDirectory: URL?
}

/// Works out what, if anything, should be repeated on the next line.
struct ListContinuation {
    /// The prefix to insert on the following line, e.g. `"- "` or `"3. "`.
    let nextPrefix: String
    /// Length in UTF-16 units of the marker on the current line.
    let prefixLength: Int
    /// True when the current line is a marker with no content after it.
    let isEmptyItem: Bool

    init?(line: String) {
        let chars = Array(line)
        var index = 0
        var prefix = ""

        func consumeWhitespace() {
            while index < chars.count, chars[index] == " " || chars[index] == "\t" {
                prefix.append(chars[index])
                index += 1
            }
        }

        consumeWhitespace()

        // Blockquote arrows repeat too.
        var sawQuote = false
        while index < chars.count, chars[index] == ">" {
            prefix.append(">")
            index += 1
            if index < chars.count, chars[index] == " " {
                prefix.append(" ")
                index += 1
            }
            sawQuote = true
            consumeWhitespace()
        }

        var marker = ""
        if index < chars.count, chars[index] == "-" || chars[index] == "*" || chars[index] == "+" {
            marker = String(chars[index])
            index += 1
        } else if index < chars.count, chars[index].isNumber {
            var digits = ""
            while index < chars.count, chars[index].isNumber, digits.count < 9 {
                digits.append(chars[index])
                index += 1
            }
            guard index < chars.count, chars[index] == "." || chars[index] == ")" else {
                if sawQuote {
                    self.nextPrefix = prefix
                    self.prefixLength = prefix.utf16.count
                    self.isEmptyItem = index >= chars.count
                    return
                }
                return nil
            }
            // Auto-numbering: the next item continues the sequence.
            let next = (Int(digits) ?? 1) + 1
            marker = "\(next)\(chars[index])"
            index += 1
        } else {
            guard sawQuote else { return nil }
            self.nextPrefix = prefix
            self.prefixLength = prefix.utf16.count
            self.isEmptyItem = index >= chars.count
            return
        }

        guard index < chars.count, chars[index] == " " || chars[index] == "\t" else {
            // "-" alone on a line is an empty item.
            guard index == chars.count else { return nil }
            self.nextPrefix = prefix + marker + " "
            self.prefixLength = (prefix + marker).utf16.count
            self.isEmptyItem = true
            return
        }
        prefix += marker + " "
        index += 1
        while index < chars.count, chars[index] == " " { index += 1 }

        var rest = String(chars[min(index, chars.count)...])

        // A task item continues as an unticked one.
        var taskPrefix = ""
        if rest.hasPrefix("[ ] ") || rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") {
            taskPrefix = "[ ] "
            rest = String(rest.dropFirst(4))
        }

        self.nextPrefix = prefix + taskPrefix
        self.prefixLength = (prefix + taskPrefix).utf16.count
        self.isEmptyItem = rest.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
