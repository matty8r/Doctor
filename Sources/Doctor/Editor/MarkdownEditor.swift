import AppKit
import SwiftUI

/// Lets menu commands reach whichever editor is in front.
final class EditorBridge {
    static let shared = EditorBridge()
    weak var textView: EditorTextView?
    private init() {}

    func perform(_ action: (EditorTextView) -> Void) {
        guard let textView else { NSSound.beep(); return }
        textView.window?.makeFirstResponder(textView)
        action(textView)
    }
}

/// Hosts the AppKit text view inside SwiftUI.
///
/// There is exactly one of these for the whole window; switching tabs swaps the
/// text in place rather than rebuilding the view, so scroll position, selection
/// and undo history all survive a round trip between tabs.
struct MarkdownEditor: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    @ObservedObject var settings: AppSettings

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, settings: settings)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layoutManager = ConcealingLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = EditorTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true          // we set attributes ourselves
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 32, height: 28)
        textView.drawsBackground = true
        textView.backgroundColor = MarkdownTheme.editorBackground
        textView.insertionPointColor = MarkdownTheme.accent
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.usesFontPanel = false
        textView.usesRuler = false

        // Substitutions that are helpful in prose and destructive in Markdown.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = settings.continuousSpellCheck
        textView.isGrammarCheckingEnabled = false

        textView.settings = settings
        textView.mode = document.mode
        textView.onOpenFiles = { urls in
            DocumentStore.shared.open(urls: urls)
        }
        textView.registerForDraggedTypes([.fileURL])

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = MarkdownTheme.editorBackground
        scrollView.borderType = .noBorder
        scrollView.postsFrameChangedNotifications = true

        context.coordinator.attach(scrollView: scrollView, textView: textView, layoutManager: layoutManager)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.settings = settings
        context.coordinator.sync(to: document)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var settings: AppSettings
        private(set) var document: MarkdownDocument

        private weak var scrollView: NSScrollView?
        private weak var textView: EditorTextView?
        private weak var layoutManager: ConcealingLayoutManager?

        /// One undo stack per tab, so undo never reaches into another document.
        private var undoManagers: [UUID: UndoManager] = [:]

        private var isApplyingModel = false
        private var highlightWork: DispatchWorkItem?
        private var appliedMode: EditorMode?
        private var appliedStyleSignature: String = ""
        /// The line the caret was last on. Concealment only changes when this does.
        private var lastRevealLine: NSRange?

        init(document: MarkdownDocument, settings: AppSettings) {
            self.document = document
            self.settings = settings
            super.init()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(scrollView: NSScrollView, textView: EditorTextView, layoutManager: ConcealingLayoutManager) {
            self.scrollView = scrollView
            self.textView = textView
            self.layoutManager = layoutManager
            EditorBridge.shared.textView = textView

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(frameChanged),
                name: NSView.frameDidChangeNotification,
                object: scrollView
            )

            loadDocument(document, force: true)
        }

        // MARK: Model synchronisation

        func sync(to newDocument: MarkdownDocument) {
            guard let textView else { return }

            if newDocument.id != document.id {
                persistViewState()
                document = newDocument
                loadDocument(newDocument, force: true)
                return
            }

            // The document was reverted or reloaded from disk underneath us.
            if textView.string != newDocument.text {
                loadDocument(newDocument, force: false)
                return
            }

            let signature = styleSignature()
            if appliedMode != newDocument.mode || appliedStyleSignature != signature {
                appliedMode = newDocument.mode
                appliedStyleSignature = signature
                textView.mode = newDocument.mode
                textView.isContinuousSpellCheckingEnabled = settings.continuousSpellCheck
                updateInsets()
                highlight(immediately: true)
            }
        }

        private func loadDocument(_ document: MarkdownDocument, force: Bool) {
            guard let textView, let storage = textView.textStorage else { return }

            isApplyingModel = true
            let previousSelection = force ? document.selectedRange : textView.selectedRange()
            storage.beginEditing()
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: document.text)
            storage.endEditing()
            isApplyingModel = false

            textView.mode = document.mode
            textView.documentDirectory = document.url?.deletingLastPathComponent()
            textView.isContinuousSpellCheckingEnabled = settings.continuousSpellCheck
            appliedMode = document.mode
            appliedStyleSignature = styleSignature()

            let length = (textView.string as NSString).length
            let clamped = NSRange(
                location: min(previousSelection.location, length),
                length: min(previousSelection.length, max(0, length - min(previousSelection.location, length)))
            )
            textView.setSelectedRange(clamped)

            updateInsets()
            highlight(immediately: true)

            if force {
                // Restore the tab's scroll position once layout has settled.
                let offset = document.scrollOffset
                DispatchQueue.main.async { [weak self] in
                    guard let scrollView = self?.textView?.enclosingScrollView else { return }
                    scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            }
        }

        private func persistViewState() {
            guard let textView else { return }
            document.selectedRange = textView.selectedRange()
            document.scrollOffset = textView.enclosingScrollView?.contentView.bounds.origin.y ?? 0
        }

        private func styleSignature() -> String {
            [
                settings.previewFontName,
                String(settings.previewFontSize),
                settings.sourceFontName,
                String(settings.sourceFontSize),
                String(settings.lineSpacing),
                String(settings.contentWidth),
                String(settings.hideSyntax),
                String(settings.continuousSpellCheck)
            ].joined(separator: "|")
        }

        // MARK: Layout

        @objc private func frameChanged() {
            updateInsets()
        }

        /// Centres the text column in preview mode. A window-wide measure is
        /// exhausting to read; a fixed column is what a document looks like.
        private func updateInsets() {
            guard let textView, let scrollView else { return }
            let available = scrollView.contentView.bounds.width
            guard available > 0 else { return }

            let vertical: CGFloat = 28
            let horizontal: CGFloat
            if document.mode == .preview {
                let target = min(CGFloat(settings.contentWidth), available - 48)
                horizontal = max(24, (available - max(320, target)) / 2)
            } else {
                horizontal = 24
            }

            let inset = NSSize(width: horizontal, height: vertical)
            if abs(textView.textContainerInset.width - inset.width) > 0.5
                || abs(textView.textContainerInset.height - inset.height) > 0.5 {
                textView.textContainerInset = inset
                textView.needsDisplay = true
            }
        }

        // MARK: Highlighting

        func highlight(immediately: Bool) {
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.applyHighlight() }
            highlightWork = work
            if immediately {
                work.perform()
            } else {
                // A short coalescing window keeps fast typing from re-parsing
                // the document on every single keystroke.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: work)
            }
        }

        private func applyHighlight() {
            guard let textView, let storage = textView.textStorage, let layoutManager else { return }

            let text = storage.string as NSString
            let selection = textView.selectedRange()
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
                mode: document.mode,
                revealRange: reveal,
                settings: settings
            )
            layoutManager.update(concealed: result.concealed, decorations: result.decorations)

            let theme = MarkdownTheme(settings: settings, mode: document.mode)
            textView.typingAttributes = [
                .font: theme.baseFont,
                .foregroundColor: MarkdownTheme.text
            ]
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !isApplyingModel, let textView else { return }
            document.text = textView.string
            highlight(immediately: false)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingModel, let textView else { return }
            document.selectedRange = textView.selectedRange()

            guard settings.hideSyntax, document.mode == .preview else { return }

            // Concealment depends on which line the caret is on — but only on
            // that. Moving along a line changes nothing, so don't re-parse.
            let text = textView.string as NSString
            guard text.length > 0 else { return }
            let selection = textView.selectedRange()
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

        func undoManager(for view: NSTextView) -> UndoManager? {
            if let existing = undoManagers[document.id] { return existing }
            let manager = UndoManager()
            manager.levelsOfUndo = 200
            undoManagers[document.id] = manager
            return manager
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        }
    }
}
