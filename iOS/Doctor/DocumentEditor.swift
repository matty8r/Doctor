import SwiftUI
import UIKit
import DoctorEditorKit

/// The document's whole surface — reading and editing are the same view,
/// the same way macOS's Preview mode always has been: punctuation on the
/// line you're on is visible and editable; everywhere else it's concealed
/// and the text reads as rendered Markdown. There's no separate plain-text
/// compose screen (that was `ComposeView`, now gone) — tap in and type.
///
/// Built the same manual TextKit 1 way as `MarkdownEditor` does on macOS —
/// `NSTextStorage` + `ConcealingLayoutManager` + `NSTextContainer`, in that
/// order — and for the same reason: `UITextView` defaults to TextKit 2 on
/// iOS 16+, which doesn't support a custom `NSLayoutManager`.
struct DocumentEditor: UIViewRepresentable {
    @Binding var text: String
    var mode: EditorMode
    var settings: ReaderSettings

    func makeCoordinator() -> Coordinator {
        Coordinator(settings: settings, mode: mode)
    }

    func makeUIView(context: Context) -> LayoutObservingTextView {
        let storage = NSTextStorage()
        let layoutManager = ConcealingLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = LayoutObservingTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        textView.backgroundColor = MarkdownTheme.editorBackground
        // Smart quotes/dashes actively corrupt Markdown punctuation (a typed
        // "--" becoming an em dash, straight quotes going curly) — the same
        // reason macOS disables the equivalent AppKit substitutions.
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no

        context.coordinator.attach(textView: textView, layoutManager: layoutManager)
        return textView
    }

    func updateUIView(_ textView: LayoutObservingTextView, context: Context) {
        context.coordinator.onTextChange = { text = $0 }
        context.coordinator.settings = settings
        context.coordinator.setMode(mode)
        context.coordinator.loadIfNeeded(text: text)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        var settings: ReaderSettings
        var onTextChange: (String) -> Void = { _ in }
        private var mode: EditorMode

        private weak var textView: LayoutObservingTextView?
        private weak var layoutManager: ConcealingLayoutManager?

        private var isApplyingModel = false
        private var highlightWork: DispatchWorkItem?
        /// The line the caret was last on. Concealment only changes when this does.
        private var lastRevealLine: NSRange?

        init(settings: ReaderSettings, mode: EditorMode) {
            self.settings = settings
            self.mode = mode
        }

        func attach(textView: LayoutObservingTextView, layoutManager: ConcealingLayoutManager) {
            self.textView = textView
            self.layoutManager = layoutManager
            // Tables need the container's real width, which doesn't exist at
            // creation time — see LayoutObservingTextView below.
            textView.onLayout = { [weak self] in self?.highlight(immediately: false) }
        }

        func setMode(_ mode: EditorMode) {
            guard self.mode != mode else { return }
            self.mode = mode
            highlight(immediately: true)
        }

        /// Loads `text` into the storage only if it actually differs from
        /// what's there — the first load, switching documents, or a CloudKit
        /// sync landing underneath the user. A no-op on every ordinary
        /// keystroke: `textViewDidChange` already updated the storage, and
        /// pushing the same string back through `replaceCharacters` would
        /// throw away the selection and undo coalescing for nothing.
        func loadIfNeeded(text: String) {
            guard let textView else { return }
            let storage = textView.textStorage
            guard storage.string != text else { return }

            isApplyingModel = true
            let selection = textView.selectedRange
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
            let length = (storage.string as NSString).length
            textView.selectedRange = NSRange(
                location: min(selection.location, length),
                length: min(selection.length, max(0, length - min(selection.location, length)))
            )
            isApplyingModel = false
            highlight(immediately: true)
        }

        // MARK: Highlighting

        func highlight(immediately: Bool) {
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.applyHighlight() }
            highlightWork = work
            if immediately {
                work.perform()
            } else {
                // Coalesces fast typing into one re-parse instead of one per
                // keystroke — same window macOS uses.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: work)
            }
        }

        private func applyHighlight() {
            guard let textView, let layoutManager else { return }
            let storage = textView.textStorage

            let text = storage.string as NSString
            let selection = textView.selectedRange
            let reveal: NSRange
            if text.length == 0 {
                reveal = NSRange(location: 0, length: 0)
            } else {
                let safe = NSRange(location: min(selection.location, max(0, text.length - 1)),
                                   length: min(selection.length, max(0, text.length - min(selection.location, text.length))))
                reveal = text.lineRange(for: safe)
            }

            lastRevealLine = reveal
            let result = MarkdownHighlighter.highlight(
                storage: storage,
                mode: mode,
                revealRange: reveal,
                settings: settings,
                containerWidth: textView.textContainer.size.width
            )
            layoutManager.update(concealed: result.concealed, decorations: result.decorations)
            textView.setNeedsDisplay()

            let theme = MarkdownTheme(settings: settings, mode: mode)
            textView.typingAttributes = [
                .font: theme.baseFont,
                .foregroundColor: MarkdownTheme.text
            ]
        }

        // MARK: UITextViewDelegate

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingModel else { return }
            onTextChange(textView.textStorage.string)
            highlight(immediately: false)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingModel, settings.hideSyntax, mode == .preview else { return }

            // Concealment depends on which line the caret is on — but only on
            // that. Moving along a line changes nothing, so don't re-parse.
            let text = textView.textStorage.string as NSString
            guard text.length > 0 else { return }
            let selection = textView.selectedRange
            let safe = NSRange(
                location: min(selection.location, max(0, text.length - 1)),
                length: min(selection.length, max(0, text.length - min(selection.location, text.length)))
            )
            let line = text.lineRange(for: safe)
            if let last = lastRevealLine, last.location == line.location, last.length == line.length {
                return
            }
            lastRevealLine = line
            highlight(immediately: true)
        }
    }
}

/// A `UITextView` that reports every layout pass, so the highlighter can
/// re-run once the container's width is the real one rather than the zero
/// it starts life with — `NSView.frameDidChangeNotification`'s job on macOS,
/// which UIKit has no equivalent for.
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
