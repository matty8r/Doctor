import Foundation

// A deliberately lightweight Markdown scanner, built for the editor rather than
// for a spec badge. It works in UTF-16 offsets (`NSRange`) so its output can be
// handed straight to `NSTextStorage` with no index translation, and it is fast
// enough to re-run on every keystroke.
//
// The HTML exporter has its own, structural parser in `HTMLRenderer`. The two
// are kept separate on purpose: this one only needs to know where things *start*,
// and that lets it stay simple.

public enum LineKind: Equatable {
    case blank
    case heading(level: Int)
    case setextUnderline(level: Int)
    case horizontalRule
    case fenceOpen(language: String)
    case fenceClose
    case codeLine
    case indentedCode
    case bullet
    case ordered
    case task(checked: Bool)
    case tableRow
    case tableDelimiter
    case frontmatterFence
    case frontmatterLine
    case paragraph

    public var isCode: Bool {
        switch self {
        case .codeLine, .indentedCode, .fenceOpen, .fenceClose: return true
        default: return false
        }
    }

    public var isListItem: Bool {
        switch self {
        case .bullet, .ordered, .task: return true
        default: return false
        }
    }
}

public struct LineToken {
    public var range: NSRange
    public var kind: LineKind
    /// Punctuation that carries no meaning once the line is styled — hashes,
    /// list bullets, quote arrows. These are what preview mode hides.
    public var markers: [NSRange]
    /// The part of the line that reads as text.
    public var content: NSRange
    public var quoteDepth: Int
    /// Leading whitespace in columns, used for list nesting depth.
    public var indent: Int
}

public enum InlineKind {
    case code
    case strong
    case emphasis
    case strongEmphasis
    case strikethrough
    case highlight
    case link
    case image
    case wikiLink
    case autolink
    case bareURL
    case tag
    case footnoteRef
}

public struct InlineToken {
    public var range: NSRange
    public var kind: InlineKind
    public var markers: [NSRange]
    public var content: NSRange
    /// Link and image destinations: styled distinctly and hidden in preview.
    public var destination: NSRange?
}

public enum MarkdownSyntax {

    // MARK: - Lines

    public static func lineRanges(in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        let length = text.length
        var location = 0

        while location < length {
            var start = 0, end = 0, contentsEnd = 0
            text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                              for: NSRange(location: location, length: 0))
            ranges.append(NSRange(location: start, length: contentsEnd - start))
            if end <= location { break }
            location = end
        }

        // A document that ends in a newline has one more, empty, line; one that
        // doesn't, does not. Getting this wrong misplaces every attribute after it.
        if ranges.isEmpty || (length > 0 && isLineTerminator(text.character(at: length - 1))) {
            ranges.append(NSRange(location: length, length: 0))
        }
        return ranges
    }

    private static func isLineTerminator(_ unit: unichar) -> Bool {
        unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029
    }

    public static func scan(_ text: NSString) -> [LineToken] {
        let ranges = lineRanges(in: text)
        var tokens: [LineToken] = []
        tokens.reserveCapacity(ranges.count)

        var inFence = false
        var fenceChar: Character = "`"
        var fenceLength = 0
        var inFrontmatter = false
        var inTable = false

        let raw: [String] = ranges.map { text.substring(with: $0) }

        for (index, range) in ranges.enumerated() {
            let line = raw[index]
            var token = LineToken(range: range, kind: .paragraph, markers: [],
                                  content: range, quoteDepth: 0, indent: 0)

            let chars = Array(line)

            // ---- Frontmatter -------------------------------------------------
            let trimmedWhole = line.trimmingCharacters(in: .whitespaces)
            if index == 0 && trimmedWhole == "---" {
                inFrontmatter = true
                token.kind = .frontmatterFence
                token.content = NSRange(location: range.location, length: 0)
                token.markers = [range]
                tokens.append(token)
                continue
            }
            if inFrontmatter {
                if trimmedWhole == "---" || trimmedWhole == "..." {
                    inFrontmatter = false
                    token.kind = .frontmatterFence
                    token.markers = [range]
                    token.content = NSRange(location: range.location, length: 0)
                } else {
                    token.kind = .frontmatterLine
                }
                tokens.append(token)
                continue
            }

            // ---- Blockquote prefix -------------------------------------------
            var cursor = 0
            var quoteDepth = 0
            var markers: [NSRange] = []

            func skipSpaces() {
                while cursor < chars.count && (chars[cursor] == " " || chars[cursor] == "\t") { cursor += 1 }
            }

            if !inFence {
                var probe = cursor
                while probe < chars.count {
                    var spaceRun = probe
                    while spaceRun < chars.count && chars[spaceRun] == " " { spaceRun += 1 }
                    guard spaceRun < chars.count, chars[spaceRun] == ">" else { break }
                    var markerEnd = spaceRun + 1
                    if markerEnd < chars.count && chars[markerEnd] == " " { markerEnd += 1 }
                    markers.append(utf16Range(of: chars, from: probe, to: markerEnd, base: range.location))
                    quoteDepth += 1
                    probe = markerEnd
                    cursor = markerEnd
                }
            }

            let indentStart = cursor
            skipSpaces()
            let indent = cursor - indentStart
            token.quoteDepth = quoteDepth
            token.indent = indent
            token.markers = markers

            let bodyStart = cursor
            let body = String(chars[min(bodyStart, chars.count)...])
            let trimmed = body.trimmingCharacters(in: .whitespaces)

            func contentRange(from offset: Int) -> NSRange {
                utf16Range(of: chars, from: offset, to: chars.count, base: range.location)
            }

            // ---- Fenced code -------------------------------------------------
            if let fence = fenceInfo(trimmed) {
                if inFence {
                    if fence.character == fenceChar && fence.length >= fenceLength && fence.info.isEmpty {
                        inFence = false
                        token.kind = .fenceClose
                        token.markers.append(contentRange(from: bodyStart))
                        token.content = NSRange(location: range.location + range.length, length: 0)
                        tokens.append(token)
                        continue
                    }
                } else {
                    inFence = true
                    fenceChar = fence.character
                    fenceLength = fence.length
                    inTable = false
                    token.kind = .fenceOpen(language: fence.info)
                    // Hide the backticks, keep the language: "swift" is information,
                    // "```" is punctuation.
                    let fenceEnd = bodyStart + fence.length
                    token.markers.append(utf16Range(of: chars, from: bodyStart,
                                                    to: fenceEnd, base: range.location))
                    token.content = contentRange(from: fenceEnd)
                    tokens.append(token)
                    continue
                }
            }

            if inFence {
                token.kind = .codeLine
                token.content = contentRange(from: bodyStart)
                tokens.append(token)
                continue
            }

            // ---- Blank -------------------------------------------------------
            if trimmed.isEmpty {
                token.kind = .blank
                token.content = NSRange(location: range.location + range.length, length: 0)
                inTable = false
                tokens.append(token)
                continue
            }

            // ---- Headings ----------------------------------------------------
            if let level = atxHeadingLevel(body) {
                var hashEnd = bodyStart
                while hashEnd < chars.count && chars[hashEnd] == "#" { hashEnd += 1 }
                var afterHash = hashEnd
                while afterHash < chars.count && chars[afterHash] == " " { afterHash += 1 }
                token.kind = .heading(level: level)
                token.markers.append(utf16Range(of: chars, from: bodyStart, to: afterHash, base: range.location))
                token.content = contentRange(from: afterHash)
                inTable = false
                tokens.append(token)
                continue
            }

            // ---- Setext underline (only when it follows a paragraph) ----------
            if let previous = tokens.last, previous.kind == .paragraph,
               let level = setextLevel(trimmed) {
                token.kind = .setextUnderline(level: level)
                token.markers.append(contentRange(from: bodyStart))
                token.content = NSRange(location: range.location, length: 0)
                tokens.append(token)
                continue
            }

            // ---- Horizontal rule ---------------------------------------------
            if isHorizontalRule(trimmed) {
                token.kind = .horizontalRule
                token.markers.append(contentRange(from: bodyStart))
                token.content = NSRange(location: range.location, length: 0)
                inTable = false
                tokens.append(token)
                continue
            }

            // ---- Tables --------------------------------------------------------
            if body.contains("|") {
                if isTableDelimiter(trimmed) && inTable {
                    token.kind = .tableDelimiter
                    token.markers.append(contentRange(from: bodyStart))
                    token.content = NSRange(location: range.location, length: 0)
                    tokens.append(token)
                    continue
                }
                if inTable {
                    token.kind = .tableRow
                    token.content = contentRange(from: bodyStart)
                    tokens.append(token)
                    continue
                }
                // A header row is only a header if a delimiter follows it.
                if index + 1 < raw.count,
                   isTableDelimiter(raw[index + 1].trimmingCharacters(in: .whitespaces)) {
                    inTable = true
                    token.kind = .tableRow
                    token.content = contentRange(from: bodyStart)
                    tokens.append(token)
                    continue
                }
            }

            // ---- Lists -----------------------------------------------------------
            if let list = listMarker(chars, from: bodyStart) {
                token.markers.append(utf16Range(of: chars, from: bodyStart, to: list.contentStart, base: range.location))
                if let checked = list.taskChecked {
                    token.kind = .task(checked: checked)
                    token.markers.append(utf16Range(of: chars, from: list.contentStart,
                                                    to: list.textStart, base: range.location))
                    token.content = contentRange(from: list.textStart)
                } else {
                    token.kind = list.ordered ? .ordered : .bullet
                    token.content = contentRange(from: list.contentStart)
                }
                inTable = false
                tokens.append(token)
                continue
            }

            // ---- Indented code ---------------------------------------------------
            if indent >= 4, quoteDepth == 0,
               let previous = tokens.last,
               previous.kind == .blank || previous.kind == .indentedCode {
                token.kind = .indentedCode
                token.content = contentRange(from: bodyStart)
                tokens.append(token)
                continue
            }

            // ---- Paragraph -------------------------------------------------------
            token.kind = .paragraph
            token.content = contentRange(from: bodyStart)
            tokens.append(token)
        }

        return tokens
    }

    // MARK: - Line helpers

    private static func utf16Range(of chars: [Character], from: Int, to: Int, base: Int) -> NSRange {
        let lower = max(0, min(from, chars.count))
        let upper = max(lower, min(to, chars.count))
        let prefixLength = String(chars[0..<lower]).utf16.count
        let spanLength = String(chars[lower..<upper]).utf16.count
        return NSRange(location: base + prefixLength, length: spanLength)
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
        // An info string may not contain backticks for a backtick fence.
        if first == "`" && info.contains("`") { return nil }
        return (first, length, info)
    }

    private static func atxHeadingLevel(_ body: String) -> Int? {
        var level = 0
        var index = body.startIndex
        while index < body.endIndex, body[index] == "#" {
            level += 1
            index = body.index(after: index)
        }
        guard (1...6).contains(level) else { return nil }
        if index == body.endIndex { return level }
        return body[index] == " " ? level : nil
    }

    private static func setextLevel(_ trimmed: String) -> Int? {
        guard !trimmed.isEmpty else { return nil }
        if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if trimmed.count >= 2 && trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let stripped = trimmed.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3, let first = stripped.first,
              first == "-" || first == "*" || first == "_"
        else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    public static func isTableDelimiter(_ trimmed: String) -> Bool {
        guard trimmed.contains("-"), trimmed.contains("|") || trimmed.hasPrefix(":") else { return false }
        let cells = splitTableRow(trimmed)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            guard !c.isEmpty else { return false }
            var body = Substring(c)
            if body.hasPrefix(":") { body = body.dropFirst() }
            if body.hasSuffix(":") { body = body.dropLast() }
            return !body.isEmpty && body.allSatisfy { $0 == "-" }
        }
    }

    /// Splits a table row on unescaped pipes, dropping the optional outer ones.
    public static func splitTableRow(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var escaped = false
        var inCode = false

        for ch in line {
            if escaped {
                current.append(ch)
                escaped = false
                continue
            }
            switch ch {
            case "\\":
                escaped = true
                current.append(ch)
            case "`":
                inCode.toggle()
                current.append(ch)
            case "|" where !inCode:
                cells.append(current)
                current = ""
            default:
                current.append(ch)
            }
        }
        cells.append(current)

        if let first = cells.first, first.trimmingCharacters(in: .whitespaces).isEmpty { cells.removeFirst() }
        if let last = cells.last, last.trimmingCharacters(in: .whitespaces).isEmpty { cells.removeLast() }
        return cells
    }

    private struct ListMarkerInfo {
        var ordered: Bool
        /// Offset just past the bullet or number, where item text begins.
        var contentStart: Int
        var taskChecked: Bool?
        /// For task items, the offset past the `[x]` box.
        var textStart: Int
    }

    private static func listMarker(_ chars: [Character], from start: Int) -> ListMarkerInfo? {
        var index = start
        guard index < chars.count else { return nil }

        var ordered = false
        if chars[index] == "-" || chars[index] == "*" || chars[index] == "+" {
            index += 1
        } else if chars[index].isNumber {
            var digits = 0
            while index < chars.count, chars[index].isNumber, digits < 9 {
                index += 1
                digits += 1
            }
            guard index < chars.count, chars[index] == "." || chars[index] == ")" else { return nil }
            index += 1
            ordered = true
        } else {
            return nil
        }

        // A marker must be followed by whitespace, or be an empty item.
        guard index < chars.count else {
            return ListMarkerInfo(ordered: ordered, contentStart: index, taskChecked: nil, textStart: index)
        }
        guard chars[index] == " " || chars[index] == "\t" else { return nil }
        while index < chars.count, chars[index] == " " || chars[index] == "\t" { index += 1 }

        // Task list box?
        if index + 2 < chars.count, chars[index] == "[", chars[index + 2] == "]" {
            let inner = chars[index + 1]
            if inner == " " || inner == "x" || inner == "X" {
                var textStart = index + 3
                while textStart < chars.count, chars[textStart] == " " { textStart += 1 }
                return ListMarkerInfo(
                    ordered: ordered,
                    contentStart: index,
                    taskChecked: inner != " ",
                    textStart: textStart
                )
            }
        }

        return ListMarkerInfo(ordered: ordered, contentStart: index, taskChecked: nil, textStart: index)
    }

    // MARK: - Inline spans

    private struct InlinePattern {
        let kind: InlineKind
        let regex: NSRegularExpression
        let contentGroup: Int
        let markerGroups: [Int]
        let destinationGroup: Int?
    }

    private static func pattern(_ raw: String) -> NSRegularExpression {
        // These are fixed, developer-authored patterns; a failure here is a bug,
        // not a runtime condition.
        do {
            return try NSRegularExpression(pattern: raw, options: [])
        } catch {
            fatalError("Invalid Markdown pattern \(raw): \(error)")
        }
    }

    private static let patterns: [InlinePattern] = [
        InlinePattern(kind: .code,
                      regex: pattern("(`+)([^`]+?)(\\1)(?!`)"),
                      contentGroup: 2, markerGroups: [1, 3], destinationGroup: nil),
        InlinePattern(kind: .image,
                      regex: pattern("(!\\[)([^\\]\\n]*)(\\]\\()\\s*([^)\\s]+)(?:\\s+\"[^\"\\n]*\")?(\\))"),
                      contentGroup: 2, markerGroups: [1, 3, 5], destinationGroup: 4),
        InlinePattern(kind: .footnoteRef,
                      regex: pattern("(\\[\\^)([^\\]\\n]+)(\\])"),
                      contentGroup: 2, markerGroups: [1, 3], destinationGroup: nil),
        InlinePattern(kind: .wikiLink,
                      regex: pattern("(\\[\\[)([^\\]\\n]+?)(\\]\\])"),
                      contentGroup: 2, markerGroups: [1, 3], destinationGroup: nil),
        InlinePattern(kind: .link,
                      regex: pattern("(?<!\\!)(\\[)([^\\]\\n]*)(\\]\\()\\s*([^)\\s]+)(?:\\s+\"[^\"\\n]*\")?(\\))"),
                      contentGroup: 2, markerGroups: [1, 3, 5], destinationGroup: 4),
        InlinePattern(kind: .autolink,
                      regex: pattern("(<)([a-zA-Z][a-zA-Z0-9+.\\-]*:[^>\\s]+)(>)"),
                      contentGroup: 2, markerGroups: [1, 3], destinationGroup: nil),
        InlinePattern(kind: .bareURL,
                      regex: pattern("(?<![\\(\\[<\"'])https?://[^\\s<>\\)\\]\"']+"),
                      contentGroup: 0, markerGroups: [], destinationGroup: nil),
        InlinePattern(kind: .strongEmphasis,
                      regex: pattern("(\\*\\*\\*)(?=\\S)(.+?)(?<=\\S)(\\*\\*\\*)"),
                      contentGroup: 2, markerGroups: [1, 3], destinationGroup: nil),
        InlinePattern(kind: .strong,
                      regex: pattern("(\\*\\*)(?=\\S)((?:[^*]|\\*(?!\\*))+?)(?<=\\S)(\\*\\*)"),
                      contentGroup: 2, markerGroups: [1, 3], destinationGroup: nil),
        InlinePattern(kind: .strong,
                      regex: pattern("(?<![A-Za-z0-9_])(__)(?=\\S)(.+?)(?<=\\S)(__)(?![A-Za-z0-9_])"),
                      contentGroup: 2, markerGroups: [1, 3], destinationGroup: nil),
        InlinePattern(kind: .strikethrough,
                      regex: pattern("(~~)(?=\\S)(.+?)(?<=\\S)(~~)"),
                      contentGroup: 2, markerGroups: [1, 3], destinationGroup: nil),
        InlinePattern(kind: .highlight,
                      regex: pattern("(==)(?=\\S)(.+?)(?<=\\S)(==)"),
                      contentGroup: 2, markerGroups: [1, 3], destinationGroup: nil),
        InlinePattern(kind: .emphasis,
                      regex: pattern("(?<!\\*)(\\*)(?=[^\\s*])([^*]+?)(?<=[^\\s*])(\\*)(?!\\*)"),
                      contentGroup: 2, markerGroups: [1, 3], destinationGroup: nil),
        InlinePattern(kind: .emphasis,
                      regex: pattern("(?<![A-Za-z0-9_])(_)(?=[^\\s_])([^_]+?)(?<=[^\\s_])(_)(?![A-Za-z0-9_])"),
                      contentGroup: 2, markerGroups: [1, 3], destinationGroup: nil),
        InlinePattern(kind: .tag,
                      regex: pattern("(?<![\\w&/])#([A-Za-z][A-Za-z0-9_/\\-]*)"),
                      contentGroup: 0, markerGroups: [], destinationGroup: nil)
    ]

    /// Finds inline spans within `range`. Patterns are tried in priority order and
    /// later matches that overlap earlier ones are dropped, which is what makes
    /// `` `**not bold**` `` behave.
    public static func inlineTokens(in text: NSString, range: NSRange) -> [InlineToken] {
        inlineTokens(in: text, source: text as String, range: range)
    }

    /// Bridging an `NSString` to `String` on every line turns a linear pass into
    /// a quadratic one, so callers that scan many lines pass the bridged string
    /// in once.
    public static func inlineTokens(in text: NSString, source: String, range: NSRange) -> [InlineToken] {
        guard range.length > 0 else { return [] }

        var claimed: [NSRange] = []
        var tokens: [InlineToken] = []

        func overlapsClaimed(_ candidate: NSRange) -> Bool {
            for existing in claimed where NSIntersectionRange(existing, candidate).length > 0 {
                return true
            }
            return false
        }

        for pattern in patterns {
            pattern.regex.enumerateMatches(in: source, options: [], range: range) { match, _, _ in
                guard let match else { return }
                let whole = match.range
                guard whole.length > 0, !overlapsClaimed(whole) else { return }

                let content = pattern.contentGroup == 0 ? whole : match.range(at: pattern.contentGroup)
                guard content.location != NSNotFound else { return }

                var markers: [NSRange] = []
                for group in pattern.markerGroups {
                    let markerRange = match.range(at: group)
                    if markerRange.location != NSNotFound && markerRange.length > 0 {
                        markers.append(markerRange)
                    }
                }

                var destination: NSRange?
                if let group = pattern.destinationGroup {
                    let destinationRange = match.range(at: group)
                    if destinationRange.location != NSNotFound && destinationRange.length > 0 {
                        // The whitespace and title between the URL and `)` should
                        // vanish with it in preview.
                        let closeMarker = markers.last
                        let end = closeMarker.map { $0.location } ?? NSMaxRange(destinationRange)
                        destination = NSRange(location: destinationRange.location,
                                              length: max(0, end - destinationRange.location))
                    }
                }

                claimed.append(whole)
                tokens.append(InlineToken(range: whole, kind: pattern.kind,
                                          markers: markers, content: content,
                                          destination: destination))
            }
        }

        tokens.sort { $0.range.location < $1.range.location }
        return tokens
    }
}
