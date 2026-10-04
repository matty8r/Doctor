import Foundation

/// Flips a task's checkbox — `- [ ] ` to `- [x] ` and back — for a tap on
/// the drawn checkbox rather than typing. Both forms are 3 characters
/// (`[ ]`/`[x]`), so the edit never changes the document's overall length,
/// which matters to the caller: it means whatever the caret's existing
/// position was elsewhere in the document stays numerically valid without
/// adjustment, so tapping a checkbox can toggle it in place without moving
/// the caret there or revealing that line's raw Markdown — the point of
/// this existing at all (a tap used to just place the caret, which on a
/// concealed task line meant entering edit mode to check a box).
enum ChecklistToggle {

    /// `nil` when the line containing `location` isn't a task item.
    static func apply(text: String, location: Int) -> String? {
        let ns = text as NSString
        let safeLocation = min(max(location, 0), ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: safeLocation, length: 0))
        var lineText = ns.substring(with: lineRange)
        let hasNewline = lineText.hasSuffix("\n")
        if hasNewline { lineText.removeLast() }

        let indent = String(lineText.prefix { $0 == " " || $0 == "\t" })
        let body = String(lineText.dropFirst(indent.count))

        let flippedBody: String
        if body.hasPrefix("- [ ] ") {
            flippedBody = "- [x] " + body.dropFirst(6)
        } else if body.hasPrefix("- [x] ") {
            flippedBody = "- [ ] " + body.dropFirst(6)
        } else {
            return nil
        }

        let out = NSMutableString(string: text)
        out.replaceCharacters(in: lineRange, with: indent + flippedBody + (hasNewline ? "\n" : ""))
        return out as String
    }
}
