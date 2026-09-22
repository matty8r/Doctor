import AppKit
import SwiftUI

/// A quiet line of counts under the text. The mode switch lives in the toolbar
/// and the file's location in the title bar, so this carries nothing else.
struct StatusBar: View {
    @ObservedObject var document: MarkdownDocument

    var body: some View {
        HStack {
            Spacer()
            Text(statistics)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .frame(height: 24)
        .background(Color(nsColor: MarkdownTheme.editorBackground))
    }

    private var statistics: String {
        let words = document.wordCount
        var parts = [
            "\(words) word\(words == 1 ? "" : "s")",
            "\(document.characterCount) char\(document.characterCount == 1 ? "" : "s")"
        ]
        if words > 0 { parts.append("\(document.readingMinutes) min read") }
        return parts.joined(separator: "  ·  ")
    }
}
