import SwiftUI
import UIKit
import DoctorEditorKit

/// Renders Markdown the same way the Mac app's Preview mode does — same
/// theme, same highlighter, same `ConcealingLayoutManager` — hosted in a
/// read-only `UITextView` built the manual TextKit 1 way, the way macOS
/// builds its `NSTextView`. `UITextView` defaults to TextKit 2 on iOS 16+,
/// which doesn't support a custom `NSLayoutManager`; building the container
/// stack explicitly, the same three objects in the same order, is what keeps
/// this the same engine rather than a reimplementation of it.
///
/// Read-only for now: no `MarkdownEditing`, no format bar. See docs/ios.md
/// for why that's the v1 line, not an oversight.
struct ReaderView: UIViewRepresentable {
    var text: String
    var settings: ReaderSettings = ReaderSettings()

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> LayoutObservingTextView {
        let storage = NSTextStorage()
        let layoutManager = ConcealingLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = LayoutObservingTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        textView.backgroundColor = MarkdownTheme.editorBackground

        context.coordinator.layoutManager = layoutManager
        // Tables need the container's real width, which doesn't exist yet at
        // creation time (the view is still .zero) — only once SwiftUI has
        // actually laid it out. `NSView.frameDidChangeNotification` is what
        // macOS uses for the equivalent case; UIKit has no notification for
        // it, so the text view itself reports its own layout passes instead.
        textView.onLayout = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.apply(text: text, settings: settings, to: textView)
        }
        context.coordinator.apply(text: text, settings: settings, to: textView)
        return textView
    }

    func updateUIView(_ textView: LayoutObservingTextView, context: Context) {
        context.coordinator.apply(text: text, settings: settings, to: textView)
    }

    final class Coordinator {
        weak var layoutManager: ConcealingLayoutManager?
        private var appliedText: String?
        private var appliedWidth: CGFloat = 0

        func apply(text: String, settings: ReaderSettings, to textView: UITextView) {
            let width = textView.textContainer.size.width
            guard text != appliedText || abs(width - appliedWidth) > 1 else { return }
            appliedText = text
            appliedWidth = width

            guard let storage = textView.textStorage as NSTextStorage?, let layoutManager else { return }
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)

            let result = MarkdownHighlighter.highlight(
                storage: storage,
                mode: .preview,
                revealRange: NSRange(location: 0, length: 0),
                settings: settings,
                containerWidth: width
            )
            layoutManager.update(concealed: result.concealed, decorations: result.decorations)
            textView.setNeedsDisplay()
        }
    }
}

/// A `UITextView` that reports every layout pass, so the highlighter can
/// re-run once the container's width is the real one rather than the zero
/// it starts life with.
final class LayoutObservingTextView: UITextView {
    var onLayout: (() -> Void)?
    private var lastReportedWidth: CGFloat = -1

    override func layoutSubviews() {
        super.layoutSubviews()
        guard abs(textContainer.size.width - lastReportedWidth) > 1 else { return }
        lastReportedWidth = textContainer.size.width
        onLayout?()
    }
}
