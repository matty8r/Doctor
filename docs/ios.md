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
- **`MarkdownEditing` (the Format-menu commands) still hasn't moved** — see
  "Editing in place" below for what *did*: the live-preview-is-editable
  mechanic itself, which is a different, smaller piece of Mac's editor
  (`MarkdownEditor`'s Coordinator, not `MarkdownEditing.swift`).
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
| `MarkdownEditing` (the Format-menu commands — bold/italic shortcuts, list continuation, heading levels) | ~300 | **Still not moving.** `DocumentEditor` ported the *live-preview-is-editable* mechanic (concealment follows the caret, typing re-highlights) from `MarkdownEditor`'s Coordinator — that's a different ~150 lines, not this file. No formatting toolbar exists yet. |
| `EditorTextView`, `MarkdownEditor` | ~690 (mac equivalent) | **Done — ported, not a straight line-for-line port.** `DocumentEditor.swift`'s Coordinator mirrors `MarkdownEditor.Coordinator` directly: `loadIfNeeded`/`highlight(immediately:)`/`textViewDidChange`/`textViewDidChangeSelection` are the same shape, same debounce window, same "which line is the caret on" logic. What didn't carry over: undo-manager-per-tab (one document per screen, `UITextView`'s own undo manager is enough), `clickedOnLink`, Obsidian's document-directory plumbing. |
| `DocumentStore`, `AppDelegate`, `DoctorCommands`, tab UI | ~790 | **Dropped**, replaced by the CloudKit-backed library (list view + a SwiftData `Document` model) — genuinely new, no mac equivalent to point at. |
| `ExportService` | ~180 | **Not v1.** No print/PDF export yet. |
| `ObsidianService` | ~130 | **Not v1.** Deferred per the Sync/Obsidian decisions above. |

## The CloudKit library (2026-10-03) — built

Not raw `CKRecord` CRUD after all. Feed Me, Seymour!'s `Persistence.swift`
uses SwiftData with a CloudKit-backed `ModelConfiguration`
(`cloudKitDatabase: .automatic`) — built on `NSPersistentCloudKitContainer`
under the hood, same as Core Data's CloudKit integration — and that's a far
smaller amount of code than hand-rolling CKRecord save/fetch/delete plus a
sync coordinator. Doctor uses the same pattern, simpler by one tier:

- **One model, not two.** FMS splits a local-only store (article bodies,
  re-fetchable from the feed) from a small CloudKit-mirrored one (read/star
  state) and reconciles them by hand (`SyncCoordinator.swift`) because
  SwiftData won't let a CloudKit-backed model relate to a local-only one.
  A Doctor document has no "origin to re-fetch from" — the body *is* the
  content — so there's nothing to split. `iOS/Doctor/Document.swift` is a
  single `@Model`, the whole store is one `ModelConfiguration`.
- **Body is a plain `String`.** The "`CKAsset` past some threshold" question
  the port map raised turned out not to need an answer yet: a Markdown note
  is at most a few hundred KB, comfortably inside what a CloudKit record
  field holds, and CloudKit externalizes a field to its own asset storage on
  its own if one ever got large enough to need it. Revisit only if that
  stops being true in practice.
- **No manual conflict layer.** `modifiedAt` exists as a last-writer-wins
  clock, but nothing in Doctor's code resolves conflicts — SwiftData's
  CloudKit backing does that at the whole-record level by itself, the way
  Core Data + CloudKit always has. For one person's own notes synced across
  their own devices, "whichever device saved last wins" is the right
  default; a real three-way text merge isn't attempted and shouldn't be.
- **`Persistence.swift`** mirrors FMS's fallback ladder (cloud-backed →
  local-only if the store can't open with CloudKit → in-memory as a last
  resort rather than a crash at launch) and its `seedIfEmpty` naming
  convention, for a one-document seed so a fresh install isn't empty.
- **`ComposeView` is not `MarkdownEditing`.** It's a bare SwiftUI `TextField`
  + `TextEditor` — no formatting commands, no live concealment, no syntax
  highlighting while typing — and exists only so content can get into the
  library before a share extension does. Don't confuse it with the deferred
  "editing on a phone" problem below; it's a different, much smaller thing,
  there only because the library needed *some* way in to be testable at all.

Verified live in Simulator, not just by building: empty state → seeded
document in the list → tapped open → rendered via `ReaderView` (table, code
block, rule, same as the earlier screenshot) → "+" made a new one → typed a
title and body through hardware-keyboard passthrough → Done → back in the
list, sorted newest-edited-first, the seeded document's own `modifiedAt`
untouched by editing the other one.

**Superseded the same day** — see the next section. `ComposeView` and the
read-only `ReaderView` it describes are both gone.

## Editing in place (2026-10-03) — built

The reading screen *is* the editing screen now, the way macOS's Preview mode
always has been — not a separate plain-text compose sheet. `ComposeView.swift`
is deleted; `ReaderView.swift` became `DocumentEditor.swift`, with
`isEditable = true` and a `UITextViewDelegate` Coordinator ported from
`MarkdownEditor`'s (see the port-map row above). Title and body are both
`@Bindable`-bound straight to the SwiftData `Document`, so typing anywhere —
title included — writes directly into the CloudKit-backed model; no sheet, no
separate save step beyond SwiftData's own autosave plus an explicit
`context.save()` on `.onDisappear`.

**A raw/interpreted switch**, matching macOS's Preview/Source toolbar control:
a two-icon segmented `Picker` bound to `EditorMode` (already in
`DoctorEditorKit`, unchanged) in `DocumentDetailView`'s toolbar. Switching
modes re-highlights immediately, same `MarkdownHighlighter.highlight(mode:)`
call Mac's `sync(to:)` makes.

**A font preference** — serif or sans, the smaller ask alongside the editing
change. Verified before writing any product code, not assumed:
`UIFont(name: "New York", size:)` returns `nil` on the real iOS 17 SDK, and
so does `NSFont(name: "New York", size:)` on macOS — compiled and ran a tiny
probe binary via `xcrun simctl spawn` to check, rather than trust memory of
how the API works. New York exists only through the design-aware path,
`UIFontDescriptor`/`NSFontDescriptor.withDesign(.serif)`, which resolves to
the private `.NewYork-*` family identically on both platforms. That's now
`Platform.systemFont(ofSize:weight:design:)` in `PlatformTypes.swift`, and a
new `previewFontDesign` requirement on `MarkdownThemeSettings` — defaulted to
`.default` via a protocol extension, so `AppSettings` on macOS needed no
changes at all to keep conforming. `ReaderPreferences` (new,
`UserDefaults`-backed, the iOS analogue of `AppSettings` minus everything
Mac-only) persists the choice; `ReaderSettingsView` is the one-screen Form
that sets it, deliberately much smaller than Mac's full font-family picker.

**A debugging note worth keeping**: most of the "the button isn't working"
time during this session's verification was the Simulator's own window
silently moving between tool calls (AppleScript's reported window position
going stale), not a code bug — confirmed by the fact that a button proven
working minutes earlier also stopped responding, at the same old coordinates,
at the same time. Re-fetch the window's position immediately before any
click rather than reusing a cached one from even a few calls ago.

Verified live in Simulator: concealment follows the caret exactly like
macOS (tapped a heading, watched its `#` appear and the previous line's
disappear), typed new text mid-document and watched it render correctly,
force-quit and relaunched the app and confirmed the typed text survived
(SwiftData persistence, not just in-memory state), toggled raw/interpreted
and watched the same document switch to full source and back, and switched
the font to Serif in Settings and watched the live preview render in New
York.

## Open problems

**Project structure — decided.** XcodeGen (already on this machine), generating
an Xcode project under `iOS/` from a checked-in `project.yml`, alongside —
not replacing — the SwiftPM `Makefile` + `build-app.sh` macOS build. The iOS
project depends on `DoctorMarkdown` and `DoctorEditorKit` as local Swift
package dependencies.

**A formatting toolbar is still not attempted.** The live-preview-is-editable
mechanic is built (see above) — what's still missing is `MarkdownEditing`'s
actual commands: bold/italic shortcuts, heading levels, list continuation on
Return, Tab to indent. None of that has an iOS UI yet (there's no keyboard
shortcut story on a phone the way there is on a Mac menu bar; this needs its
own design, likely a keyboard accessory view, not a straight port).

**Portal work, not code** — needed before this leaves Simulator: the
existing `com.matty8r.Doctor` App ID needs iCloud and Push Notifications
capabilities added on the Developer Portal (it has neither today — only the
macOS app has used this App ID so far), and a provisioning profile appropriate
to wherever this goes next (TestFlight or a device build). Nothing here can
be done from the command line.

**Import path.** A share extension ("Open in Doctor") is still the cleanest
way something else hands Doctor a file, and is still not built. Not blocking
anything — the document screen's own in-place editing covers "how does
content get in" well enough to keep testing with.
