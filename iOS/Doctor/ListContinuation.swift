import Foundation

/// What pressing Return does inside a list item (or a quote): continue it on
/// the next line with the same kind of marker — the next number for an
/// ordered list, always unchecked for a task regardless of the item it
/// follows — or, when the item is empty, strip the marker and drop out of
/// the list instead, since there's nothing left to repeat. The usual
/// convention (Notes, Bear, and every other list-aware text editor).
///
/// A pure (text, selection) → result function, same shape as
/// `MarkdownEditing.apply`, for the same reason: testable without a running
/// `UITextView`.
enum ListContinuation {

    /// `nil` when the caret's line isn't a list item or quote, so the caller
    /// falls back to inserting an ordinary newline.
    static func apply(text: String, selection: NSRange) -> MarkdownEditing.Result? {
        let ns = text as NSString
        let safeSelection = NSRange(
            location: min(selection.location, ns.length),
            length: min(selection.length, max(0, ns.length - min(selection.location, ns.length)))
        )
        let storage = NSMutableString(string: text)
        storage.deleteCharacters(in: safeSelection)
        let caret = safeSelection.location

        let lineRange = (storage as NSString).lineRange(for: NSRange(location: caret, length: 0))
        var lineText = (storage as NSString).substring(with: lineRange)
        if lineText.hasSuffix("\n") { lineText.removeLast() }

        let indent = String(lineText.prefix { $0 == " " || $0 == "\t" })
        let body = String(lineText.dropFirst(indent.count))

        guard let (marker, markerLength) = marker(for: body) else { return nil }

        // Nothing but the marker on the whole line, regardless of where the
        // caret sits within it — matches `MarkdownEditing`'s own "blank line"
        // framing for these same prefixes.
        if (body as NSString).length == markerLength {
            let stripRange = NSRange(location: lineRange.location,
                                     length: (indent as NSString).length + markerLength)
            storage.deleteCharacters(in: stripRange)
            return MarkdownEditing.Result(text: storage as String, selection: NSRange(location: stripRange.location, length: 0))
        }

        let insertion = "\n" + indent + marker
        storage.insert(insertion, at: caret)
        return MarkdownEditing.Result(
            text: storage as String,
            selection: NSRange(location: caret + (insertion as NSString).length, length: 0)
        )
    }

    private static let orderedRegex = try? NSRegularExpression(pattern: #"^(\d+)\.\s"#)

    /// The marker to repeat on the new line, and how many UTF-16 units of
    /// `body` the *original* marker occupied — needed to test whether the
    /// item is empty and to strip it precisely, since an ordered marker's
    /// width varies with the number's digit count. Internal rather than
    /// private: `ListIndent` reuses it to recognize "this line is a bare,
    /// empty list item" with the same rules.
    static func marker(for body: String) -> (marker: String, length: Int)? {
        if body.hasPrefix("- [ ] ") { return ("- [ ] ", 6) }
        if body.hasPrefix("- [x] ") { return ("- [ ] ", 6) }
        if body.hasPrefix("> ") { return ("> ", 2) }
        if body.hasPrefix("- ") { return ("- ", 2) }

        if let regex = orderedRegex {
            let ns = body as NSString
            if let match = regex.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)) {
                let number = Int(ns.substring(with: match.range(at: 1))) ?? 0
                return ("\(number + 1). ", match.range.length)
            }
        }
        return nil
    }
}
