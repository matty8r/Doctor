/// How the editor displays the document. There are only two, on purpose:
/// live preview *is* the reading experience, it just happens to be editable
/// on macOS. (On iOS, for now, it's the only thing there is to look at.)
public enum EditorMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case preview
    case source

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .preview: return "Preview"
        case .source: return "Source"
        }
    }

    public var symbol: String {
        switch self {
        case .preview: return "doc.richtext"
        case .source: return "chevron.left.forwardslash.chevron.right"
        }
    }

    public var toggled: EditorMode { self == .preview ? .source : .preview }
}
