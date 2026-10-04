# Doctor for iPhone — decisions and port map

Status: **in progress.** The macOS build was green (1.2.1 shipped, 62/62 tests)
so the precondition that gated this is met. The shared rendering engine —
`DoctorEditorKit` — now exists and is verified: it type-checks clean against
the real iOS 17 SDK (`xcrun --sdk iphonesimulator swiftc -typecheck`), and the
macOS app that consumes it renders pixel-identical to before the refactor
(checked against the same table/code-block/rule test files used to catch the
1.2.x bugs). See "What actually moved" below.

**2026-10-04: first build uploaded to App Store Connect / TestFlight.**
`iOS/release.sh` is the whole pipeline now — archive, export, upload — see
"Portal work" below for everything that first run took.

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
- **Mac's own `MarkdownEditing.swift` still hasn't moved** — iOS's formatting
  toolbar (see "A formatting toolbar" below) is a *different* command layer,
  ported from Sprig rather than from Mac. The two aren't unified; see that
  section for why the command sets themselves also differ from each other.
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
| `MarkdownEditing` (Mac's own Format-menu commands) | ~300 | **Still not moving, and won't feed the iOS toolbar.** iOS's formatting commands came from Sprig instead — see "A formatting toolbar." `DocumentEditor` separately ported the *live-preview-is-editable* mechanic (concealment follows the caret) from `MarkdownEditor`'s Coordinator, a different ~150 lines of this same mac file. |
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

**A formatting toolbar — built (2026-10-04), nabbed from Sprig.** Sprig
(`ios/Sprig/` in `obsidianWeb`) already has exactly this: a Markdown
`inputAccessoryView` riding above the keyboard, and a pure-function command
layer (`MarkdownEditing.apply(_:to:selection:) -> (text, selection)`,
Foundation only) behind it. Both moved over close to verbatim —
`iOS/Doctor/MarkdownEditing.swift` (the pure logic) and the toolbar/
`UIHostingController` wiring now inside `DocumentEditor.swift`'s Coordinator.

What's genuinely different from Sprig, not copy-paste:
- **The command set matches what `DoctorMarkdown` renders**, not Sprig's own
  set. `.highlight` (`==text==`) and `.task` (`- [ ] `) are new — Doctor's
  renderer understands both, drawn from the same list the Mac app's
  `CheatSheetView` uses. Sprig's `.callout` (`> [!note]`, an Obsidian
  convention its own publish pipeline reads) is gone — Doctor's renderer has
  no special handling for it, so including the button would format text the
  app itself can't display correctly.
- **The Coordinator applies commands through the existing highlight pipeline**,
  not a bespoke update path: `apply(_ command:)` replaces the storage,
  updates the selection, pushes the new text out through the same
  `onTextChange` that ordinary typing uses, and calls `highlight(immediately:
  true)` — so a toolbar edit re-conceals/re-reveals exactly like a keystroke
  would, and tables/headings/etc. redraw correctly in the same pass.

Verified live in Simulator: selected a word, tapped Italic, watched it wrap
to `*word*` with the markers revealed (caret on that line) and the selection
preserved around the word — the trickiest path (toggle-wrap on a real
selection) working end to end, not just compiling.

**Bug (2026-10-04): the seven section commands silently did nothing on a
blank line.** Reported as "lists don't render" — they do; proven by
rendering actual `- item`/`1. item`/`- [ ] item` text through the shared
engine (`DoctorEditorKit`, unchanged, identical on both platforms) and
getting correctly indented, correctly coloured output. The real bug was one
level earlier: tapping Heading/Bullet/Numbered/Task/Quote with nothing typed
yet — the ordinary "tap the button, *then* start typing" order — inserted
nothing at all, so there was never any list text for the renderer to
render. `prefixLines`/`numberLines`/`taskLines`/`heading` all skip blank
lines by design, to leave a separator line alone inside a multi-line
selection — correct there, wrong when the blank line *is* the entire
selection, which is the common case for these seven specifically (the six
inline commands and code-block/divider were never affected: wrapping an
empty selection, or inserting a fenced block, was never conditional on
existing text).

Fixed with one new case per function, `insertAtBlankLine`, used only when
the whole target is a single blank line: insert the prefix and place the
caret right after it, not selecting what was just inserted (selecting it
would delete the prefix on the next keystroke). Verified by direct testing
of the pure function, not just by building — simulator GUI automation was
unavailable this session (`Simulator.app` unreachable mid what looks like a
macOS/Xcode update), so each of the 14 commands was run against an empty
document and confirmed to insert correctly with the caret positioned to
continue typing, and the existing toggle-on/off and multi-line behavior
(including a selection spanning a real blank separator line, which must
still be skipped) was re-run and confirmed unchanged. Worth a real
on-screen pass once Simulator's GUI is reachable again — this verification
is strong for "does the right text get produced," not a substitute for
seeing it typed.

**Portal work — done (2026-10-04), and shipped to TestFlight.** `iOS/
release.sh` now archives, signs, exports and uploads in one run. What that
took, worth keeping as a record since most of it was first-time setup that
won't repeat the same way twice:

- **`com.matty8r.Doctor` didn't exist as an Identifier at all** — not "needed
  capabilities added," genuinely didn't exist. Developer ID signing (what the
  Mac app uses) never registers one; only App Store/TestFlight distribution
  does. Created fresh: App ID with iCloud (CloudKit) + Push Notifications,
  plus the `iCloud.com.matty8r.Doctor` container.
- **The container didn't attach to the App ID on the first save** — the
  portal accepted the edit but the container checkbox came back unticked.
  Had to go back in and re-tick it.
- **The first downloaded distribution profile was stale from that failure**:
  generated before the container actually attached, so its own
  `com.apple.developer.icloud-container-identifiers` entitlement came back
  an empty array even though the capability showed enabled. Caught by
  inspecting the downloaded `.mobileprovision` directly (`security cms -D`)
  before trusting it, and confirmed the hard way — `xcodebuild archive`
  itself refused it with "doesn't support the iCloud…Container." Fix: edit
  the App ID, confirm the container is really there, then re-save the
  profile (not just re-download the same one) so it regenerates against the
  current capabilities, and re-download that.
- **Automatic signing (`-allowProvisioningUpdates`) couldn't help**: this
  machine has no Apple ID signed into Xcode's own Accounts preferences, so
  automatic signing has nothing to authenticate a portal refresh with and
  silently keeps reusing a stale cached wildcard profile instead — the
  actual error, once it surfaced, was "No Accounts: Add a new account in
  Accounts settings." `release.sh` uses manual signing throughout instead:
  an explicit certificate and profile name, no portal round-trip needed at
  build time.
- **The app icon was a placeholder with no image in it** — fine for
  Simulator, which doesn't check; App Store validation does, and rejected
  the first upload over it (`CFBundleIconName` / missing 120×120 icon).
  `Scripts/GenerateIOSIcon.swift` draws the same capsule-split mark as the
  Mac icon (`Scripts/GenerateIcon.swift`) adapted for iOS's edge-to-edge
  convention — no inset plate, no self-rounded corners, one opaque
  1024×1024 PNG (modern asset catalogs need only that single size; iOS
  generates every other rasterization itself, and requires no alpha
  channel, unlike the Mac icon).
- **`aps-environment` needed no manual fix**, unlike the Mac apps' Developer
  ID release scripts (which re-sign specifically to restore it after
  Xcode's own export drops it). Checked directly on the signed binary
  (`codesign -d --entitlements :-`) rather than assumed: Xcode resolved it
  to `production` correctly during a plain archive, matching what the
  distribution profile actually provides.
- **An App Store Connect app record had to be created separately** from the
  Developer Portal App ID — `xcrun altool --upload-app` refuses an upload
  for a bundle ID with no App Store Connect app behind it yet
  ("Unable to find Apple ID for Bundle ID"). One-time, via Apps → + → New
  App in App Store Connect.
- **Signing and upload credentials were both already on this machine** from
  prior work on other apps in this account (Feed Me, Seymour!, Sidetable):
  an Apple Distribution certificate, and an App Store Connect API key
  (`~/.appstoreconnect/private_keys/`). Neither needed setting up fresh —
  only the Issuer ID, which isn't stored anywhere locally, had to come from
  the account holder (App Store Connect → Users and Access → Integrations).
- **Export compliance** is headed off for next time rather than answered
  per-build: `ITSAppUsesNonExemptEncryption: false` in `project.yml`'s Info
  .plist properties, since Doctor uses only standard Apple networking
  (CloudKit) and genuinely qualifies for the exemption.

**Import path.** A share extension ("Open in Doctor") is still the cleanest
way something else hands Doctor a file, and is still not built. Not blocking
anything — the document screen's own in-place editing covers "how does
content get in" well enough to keep testing with.
