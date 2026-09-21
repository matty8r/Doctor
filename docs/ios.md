# Doctor for iPhone — decisions and port map

Status: **not started.** Agreed to begin only once the macOS app compiles and
preview mode is confirmed working, so the shared pieces are proven before they
get a second consumer.

## Decisions

| Question | Decision |
|---|---|
| Device | **iPhone first.** Not a universal app. iPad may follow; it is not a v1 constraint. |
| Sync | **None.** Files arrive via the Files app, Safari downloads, and the share sheet. Nothing follows automatically from the Mac. |
| Sequencing | **After the macOS build is green.** |

## What this means for the shape of the app

No tabs. No `DocumentStore`. The iPhone app is a document browser, one open
document, the same two modes, and a share sheet — closer to a greenfield build
than a port, and smaller for it.

The **share extension matters more than anything else here**. With no sync, the
only way a file reaches the app is Files, a Safari download, or "Open in Doctor"
from another app. That entry point is the product; it is not a nice-to-have.

## Port map

Measured against the macOS source, not estimated.

| Component | Lines | Status |
|---|---|---|
| `DoctorMarkdown` — scanner, HTML renderer, print CSS | ~1,770 | **Free.** Foundation only; compiles for iOS unchanged. |
| `MarkdownTheme`, `MarkdownHighlighter` | ~530 | **Shim.** Only `NSColor`, `NSFont` and `NSFontDescriptor` are AppKit. `NSTextStorage`, `NSParagraphStyle`, `NSAttributedString` and `NSRange` are shared with UIKit. |
| `ConcealingLayoutManager` | ~210 | **Mostly ports.** `NSLayoutManager.setGlyphs` and `drawBackground(forGlyphRange:at:)` have identical signatures on iOS. Note that `UITextView` defaults to TextKit 2 on iOS 16+; the TextKit 1 stack must be built explicitly, as it is on macOS. |
| `MarkdownEditing` | ~260 | **Shimmable** behind a small protocol — it only needs `string`, `selectedRange`, `textStorage` and `shouldChangeText`. |
| `EditorTextView`, `MarkdownEditor` | ~690 | **Rewrite.** `UITextView` is not `NSTextView`; no `mouseDown`, no menu validation, and text input handling differs. |
| `DocumentStore`, `AppDelegate`, `DoctorCommands`, tab UI | ~790 | **Dropped.** No tabs, no menu bar, document-based navigation instead. |
| `ExportService` | ~180 | **Half rewrite.** `WKWebView` ports; printing becomes `UIPrintInteractionController` and PDF becomes `UIMarkupTextPrintFormatter` + `UIGraphicsPDFRenderer`. |
| `ObsidianService` | ~130 | **Rewrite.** See below. |

Roughly 1,770 lines free, ~800 shimmable, ~1,800 new.

## Open problems to solve before writing code

**Obsidian filing under the iOS sandbox.** On macOS the vault is just a folder we
write to. On iOS the vault lives in an app container or iCloud Drive, so Doctor
needs a one-time `UIDocumentPickerViewController` grant plus a persisted
security-scoped bookmark. The `obsidian://new?content=` fallback sidesteps the
sandbox entirely but reintroduces the URL length limit that ruled it out on
macOS — so it is a fallback, not the plan.

**Project structure.** SwiftPM alone cannot produce an iOS `.app`. Adding an iOS
target means introducing an Xcode project (or XcodeGen) alongside the current
`Makefile` + `build-app.sh`, and keeping the macOS build working through that
change. Worth deciding deliberately rather than drifting into it.

**Editing on a phone.** Typing Markdown on an iPhone is unpleasant regardless of
how good the editor is. Reading is likely 90% of real use. The live-preview
editor is cheap to keep because the engine ports free — but the reading
experience is what should be designed first, and the editor should not be
allowed to compromise it.
