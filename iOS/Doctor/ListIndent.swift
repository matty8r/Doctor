import Foundation

/// Pressing Space at the very start of an empty list item — right after
/// Return made a fresh one — indents it one level instead of typing a
/// literal space. iOS has no Tab key on the standard keyboard, and this is
/// the moment a Tab-to-indent editor would expect it: nothing has been
/// typed into this item yet, so there's nothing a leading space could
/// usefully mean as content.
///
/// Bullets, numbered items and tasks only — not quotes. A quote nests by
/// repeating `>`, not indentation (`MarkdownSyntax` reads `>` regardless of
/// leading whitespace), so indenting a bare `> ` wouldn't nest anything, it
/// would just shift it.
enum ListIndent {

    /// `nil` when this isn't "Space at the start of an empty list item", so
    /// the caller falls back to inserting an ordinary space.
    static func apply(text: String, selection: NSRange) -> MarkdownEditing.Result? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        let caret = min(selection.location, ns.length)

        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        var lineText = ns.substring(with: lineRange)
        if lineText.hasSuffix("\n") { lineText.removeLast() }

        // The caret must be at the very end of the line -- nothing after it
        // either, not just nothing before -- or this isn't "a fresh empty
        // item", just a space typed somewhere inside one.
        guard caret == lineRange.location + (lineText as NSString).length else { return nil }

        let indent = String(lineText.prefix { $0 == " " || $0 == "\t" })
        let body = String(lineText.dropFirst(indent.count))
        guard let (marker, length) = ListContinuation.marker(for: body), marker != "> ",
              (body as NSString).length == length
        else { return nil }

        let insertAt = lineRange.location + (indent as NSString).length
        let out = NSMutableString(string: text)
        out.insert("  ", at: insertAt)
        return MarkdownEditing.Result(text: out as String, selection: NSRange(location: caret + 2, length: 0))
    }
}
