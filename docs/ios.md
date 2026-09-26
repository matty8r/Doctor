# Doctor for iPhone — decisions and port map

Status: **in progress.** The macOS build was green (1.2.1 shipped, 62/62 tests)
so the precondition that gated this is met. The shared rendering engine —
`DoctorEditorKit` — now exists and is verified: it type-checks clean against
the real iOS 17 SDK (`xcrun --sdk iphonesimulator swiftc -typecheck`), and the
macOS app that consumes it renders pixel-identical to before the refactor
(checked against the same table/code-block/rule test files used to catch the
1.2.x bugs). See "What actually moved" below.

## Decisions

| Question | Decision |
|---|---|
| Device | **iPhone first.** Not a universal app. iPad may follow; it is not a v1 constraint. |
| Sync | **CloudKit.** Documents live in the app's own library — like Notes, not like Preview — synced via the private database. Superseded 2026-09-25; see below. This is scoped to iOS for now, not a decision to add CloudKit to the Mac app. |
| Obsidian | **Not in v1.** Deferred, not dropped. |
| Sequencing | **After the macOS build is green.** Cleared. |

## What this means for the shape of the app

No tabs. No `DocumentStore` in the macOS sense. The library is a CloudKit-backed
list of documents — closer to a greenfield build than a port for this part, and
it replaces most of what the "no sync" plan below would have needed instead
(no Files-app browsing as the primary flow, no security-scoped bookmarks).

"Open in Doctor" / a share extension is still worth having as an *import* path
— a document opened from Files or another app gets copied into the library —
but it's no longer the only way in, and it's not blocking v1.

## What actually moved (2026-09-25)

The port map below was a prediction. This is what happened when the free and
shimmable pieces were actually pulled out into their own cross-platform target,
`Sources/DoctorEditorKit` (a new SwiftPM library product, depended on by both
the existing macOS `Doctor` target and, eventually, the iOS app):

- **Moved as-is, mechanically:** `MarkdownTheme`, `MarkdownHighlighter`,
  `TableLayout`/`TableGrid`, `BlockDecoration`, `ConcealingLayoutManager`,
  `EditorMode`. Every `NSColor`/`NSFont`/`NSBezierPath`/`NSRect`/`NSPoint`
  became a `PlatformColor`/`PlatformFont`/`PlatformBezierPath`/`CGRect`/`CGPoint`
  typealias (`Sources/DoctorEditorKit/PlatformTypes.swift`), true on macOS today
  and resolving to the UIKit equivalent once an iOS target links this package.
- **The five real API differences**, all isolated in `PlatformTypes.swift`
  rather than scattered through the rendering code:
  1. `NSColor(srgbRed:green:blue:alpha:)` vs. `UIColor(red:green:blue:alpha:)`.
  2. `NSFontDescriptor.SymbolicTraits.bold`/`.italic` vs. `UIFontDescriptor`'s
     `.traitBold`/`.traitItalic` — same concept, different case names.
  3. `NSFont(descriptor:size:)` is non-failable; `UIFont`'s is failable.
  4. `NSBezierPath(roundedRect:xRadius:yRadius:)` vs. `UIBezierPath(roundedRect:cornerRadius:)`.
  5. `NSGraphicsContext.current?.cgContext` vs. `UIGraphicsGetCurrentContext()`.
  A sixth, `NSFont.boundingRectForFont` having no iOS equivalent, is sidestepped
  entirely — `Platform.lineHeight(of:)` uses `.ascender - .descender`, which both
  platforms have under the same names.
- **One thing the doc didn't anticipate:** `NSAttributedString.boundingRect(with:options:)`
  and `.draw(with:options:)` need an explicit `context: nil` on iOS — the
  2-argument overload macOS accepts isn't there. Caught by the SDK type-check,
  not by reasoning about it in advance.
- **`AppSettings` didn't move.** It's still macOS-only — `UserDefaults`, a menu
  bar, an Obsidian vault path. `MarkdownTheme` now depends on a small protocol,
  `MarkdownThemeSettings` (font/size/spacing/hideSyntax), that `AppSettings`
  conforms to and that iOS's reader settings — whatever shape those take —
  will conform to separately, without either side depending on the other.
- **`MarkdownEditing` did not move**, on purpose. It works on `NSTextView`
  directly, and porting it means solving `EditorTextView`'s whole input-handling
  story on `UITextView`. Given the "reading is 90% of real use" premise below,
  v1 doesn't need it: the shared engine can host a *read-only* `UITextView`
  (`isEditable = false`, `isSelectable = true`, built the manual TextKit-1 way,
  same as macOS's `NSTextView(frame:textContainer:)`) with no editing commands
  at all.
- **Verification, not assumption:** `xcrun --sdk iphonesimulator swiftc
  -typecheck` against the arm64-ios17.0-simulator target is what actually
  caught all of the above — not reading the two SDKs' headers side by side.
  Re-run it after touching anything in `DoctorEditorKit`, before trusting a
  claim like "this is a straight port."

## The share extension, downgraded but not gone

Still worth having — it's the cleanest way something else hands Doctor a file
— but it's an *importer* into the CloudKit library now, not the only door in.

## Port map

Measured against the macOS source. The first three rows are done, not
predicted — see "What actually moved" above for exactly what each one took.

| Component | Lines | Status |
|---|---|---|
| `DoctorMarkdown` — scanner, HTML renderer, print CSS | ~1,770 | **Done — free.** Compiles for iOS unchanged; verified by SDK type-check. |
| `MarkdownTheme`, `MarkdownHighlighter`, `TableLayout` | ~880 | **Done — shimmed.** Now living in `DoctorEditorKit`. Five real API differences, all isolated in `PlatformTypes.swift`. |
| `ConcealingLayoutManager` | ~240 | **Done — ported.** `NSLayoutManager.setGlyphs`/`drawBackground(forGlyphRange:at:)` do have identical signatures on iOS, confirmed by the SDK type-check, not just by reading docs. |
| `MarkdownEditing` | ~300 | **Not moving for v1.** See "What actually moved" — v1 is read-only, so this has no iOS consumer yet. |
| `EditorTextView`, `MarkdownEditor` | ~690 (mac equivalent) | **New, not a port.** A read-only `UITextView` hosting `ConcealingLayoutManager`, built manually (TextKit 1, not the iOS 16+ default) the same way macOS does it. |
| `DocumentStore`, `AppDelegate`, `DoctorCommands`, tab UI | ~790 | **Dropped**, replaced by a CloudKit-backed library (list view + a `CKRecord` "Document" type), which didn't exist in the "no sync" version of this plan at all — genuinely new, not a mac equivalent to point at. |
| `ExportService` | ~180 | **Not v1.** No print/PDF export until there's an editor to export from. |
| `ObsidianService` | ~130 | **Not v1.** Deferred per the Sync/Obsidian decisions above. |

## Open problems

**The CloudKit library itself** is the new critical-path work the "no sync"
plan didn't have: a `CKRecord` schema (title, body, modified date — body as a
`String` field vs. a `CKAsset` past some size threshold, not yet decided), a
private-database CRUD layer, and enough conflict handling that two devices
editing offline don't clobber each other silently. Feed Me, Seymour! and the
Studio apps already have working CloudKit patterns in this account to start
from rather than inventing the entitlements/provisioning dance from scratch.

**Project structure — decided.** XcodeGen (already on this machine), generating
an Xcode project under `iOS/` from a checked-in `project.yml`, alongside —
not replacing — the SwiftPM `Makefile` + `build-app.sh` macOS build. The iOS
project depends on `DoctorMarkdown` and `DoctorEditorKit` as local Swift
package dependencies.

**Editing on a phone** is still not attempted, and that's still deliberate:
reading is most of real use, and v1 is a reader. `MarkdownEditing` and a real
`UITextView` input story are follow-on work once the reading experience and
the CloudKit library both hold up.
