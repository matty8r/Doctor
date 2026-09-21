import AppKit
import WebKit
import DoctorMarkdown

/// Print, PDF and HTML output.
///
/// All three go through the same rendered HTML, loaded into an off-screen
/// `WKWebView`. Printing a web view means macOS handles pagination, widow and
/// orphan control, and headers — work not worth reimplementing in Core Text.
enum ExportService {

    // MARK: - Public entry points

    static func printDocument(_ document: MarkdownDocument, in window: NSWindow?) {
        render(document) { webView in
            let info = printInfo()
            let operation = webView.printOperation(with: info)
            operation.showsPrintPanel = true
            operation.showsProgressPanel = true
            operation.view?.frame = pageRect(for: info)

            if let window {
                operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
            } else {
                operation.run()
            }
        }
    }

    static func exportPDF(_ document: MarkdownDocument, in window: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = baseName(for: document) + ".pdf"
        panel.canCreateDirectories = true
        panel.message = "Export as PDF"
        if let directory = document.url?.deletingLastPathComponent() { panel.directoryURL = directory }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        render(document) { webView in
            let info = printInfo()
            // Driving the print system with a save disposition gives properly
            // paginated output; `createPDF` gives one very tall page.
            info.jobDisposition = .save
            info.dictionary().setValue(url, forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue)

            let operation = webView.printOperation(with: info)
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false
            operation.view?.frame = pageRect(for: info)
            operation.run()

            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func exportHTML(_ document: MarkdownDocument) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = baseName(for: document) + ".html"
        panel.canCreateDirectories = true
        panel.message = "Export as HTML"
        if let directory = document.url?.deletingLastPathComponent() { panel.directoryURL = directory }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let html = HTMLRenderer.document(
            markdown: document.text,
            title: baseName(for: document),
            forPrint: false
        )
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            DocumentStore.shared.presentError(error, title: "Couldn't export HTML")
        }
    }

    static func copyHTMLToPasteboard(_ document: MarkdownDocument) {
        let html = HTMLRenderer.render(markdown: document.text)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(html, forType: .string)
    }

    // MARK: - Rendering plumbing

    private static var activeRenderer: WebRenderer?

    private static func render(_ document: MarkdownDocument, then body: @escaping (WKWebView) -> Void) {
        let html = HTMLRenderer.document(
            markdown: document.text,
            title: baseName(for: document),
            forPrint: true
        )
        // Relative image paths should resolve; the renderer has already stripped
        // anything that could execute.
        let baseURL = document.url?.deletingLastPathComponent()

        let renderer = WebRenderer()
        activeRenderer = renderer
        renderer.load(html: html, baseURL: baseURL) { webView in
            body(webView)
            activeRenderer = nil
        }
    }

    private static func printInfo() -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = 48
        info.bottomMargin = 48
        info.leftMargin = 48
        info.rightMargin = 48
        return info
    }

    private static func pageRect(for info: NSPrintInfo) -> NSRect {
        NSRect(
            x: 0,
            y: 0,
            width: info.paperSize.width - info.leftMargin - info.rightMargin,
            height: info.paperSize.height - info.topMargin - info.bottomMargin
        )
    }

    static func baseName(for document: MarkdownDocument) -> String {
        if let url = document.url {
            return url.deletingPathExtension().lastPathComponent
        }
        return document.firstHeading.map(MarkdownDocument.sanitizeFileName) ?? "Untitled"
    }
}

/// Loads HTML off-screen and calls back once it has laid out.
private final class WebRenderer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var completion: ((WKWebView) -> Void)?

    func load(html: String, baseURL: URL?, completion: @escaping (WKWebView) -> Void) {
        let configuration = WKWebViewConfiguration()
        // Nothing in a printed document needs to run.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 612 - 96, height: 792 - 96),
            configuration: configuration
        )
        webView.navigationDelegate = self
        self.webView = webView
        self.completion = completion

        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give web fonts and images a beat to settle before measuring pages.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, let completion = self.completion else { return }
            self.completion = nil
            completion(webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishWithFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishWithFailure(error)
    }

    private func finishWithFailure(_ error: Error) {
        completion = nil
        DocumentStore.shared.presentError(error, title: "Couldn't prepare the document")
    }
}
