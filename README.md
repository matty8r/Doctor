# Doctor

A Markdown reader and editor for macOS. The thing you double-click a `.md` file
into — like Preview, but for Markdown, and it writes as well as reads.

It exists because opening a downloaded Markdown file shouldn't mean importing it
into a knowledge base first. Doctor opens the file, renders it properly, lets you
edit it, prints it, and — when you decide it's a keeper — files it into Obsidian.

## What it does

**Tabs, one window.** New tabs, not new windows. Open files land beside what you
already have open, and the set of open tabs comes back after a restart, including
unsaved ones.

**Two views, both editable.**

- **Preview** — headings are big, bold is bold, code blocks sit on a panel,
  blockquotes get a bar. Markdown punctuation hides itself, except on the line
  the caret is on, so you can always see what you're changing. This is the
  reading view; it just happens to be typeable.
- **Source** — monospace, every character visible, syntax-coloured.

`⌘1` / `⌘2` switch; `⌘/` toggles. There is deliberately no read-only mode: one
document, one buffer, no conversion step that could mangle a file.

**Print and export.** `⌘P` prints, `⇧⌘E` writes a PDF, and there's HTML export
and copy-as-HTML. These render the document properly with a print stylesheet —
page margins, avoided breaks inside code blocks and tables, and printed links
that show their destination. What comes out of the printer isn't a screenshot of
the editor.

**Send to Obsidian.** `⇧⌘O` copies the document into a vault folder you nominate
and opens it there. It's a copy: the original stays where it was.

**Writing conveniences.** Return continues lists, blockquotes and task items and
ends them when you hit Return twice. Tab and Shift-Tab nest and un-nest.
Cmd-click follows a link. Clicking a `[ ]` ticks it. Paste is always plain text.
`⌘F` is the standard macOS find bar.

## Building

Requires macOS 13 or later and the Xcode command line tools. No Xcode project,
no package dependencies.

```sh
make            # builds build/Doctor.app
make run        # builds and launches it
make install    # copies to /Applications and registers it with LaunchServices
swift test      # runs the Markdown engine's test suite
```

To make Doctor the default Markdown app: select any `.md` file in Finder, press
`⌘I`, set **Open with** to Doctor, then click **Change All…**.

The app is ad-hoc signed and unsandboxed, so the first time it opens something in
Documents, Desktop or Downloads, macOS will ask for permission. That's expected.
Gatekeeper will also want a right-click ▸ Open the first time, since the
signature isn't from a registered developer.

## How it's put together

```
Sources/DoctorMarkdown/     The Markdown engine. Foundation only, no AppKit.
  MarkdownSyntax.swift        Scanner for the editor: where things start, in UTF-16.
  HTMLRenderer.swift          Structural parser for print/PDF/HTML export.
  PrintStylesheet.swift       The print and export CSS.

Sources/Doctor/             The app.
  Models/                     Settings, one document per tab, the tab store.
  Markdown/                   Turning scanner output into text attributes.
  Editor/                     The NSTextView and the layout manager behind preview.
  UI/                         SwiftUI chrome: tabs, status bar, settings, menus.
  Services/                   Export, Obsidian, external-change watching.

Tests/DoctorMarkdownTests/  Tests for the engine.
```

There are two Markdown parsers, on purpose. The editor's scanner only needs to
know where each construct *starts*, so it can stay simple and run on every
keystroke. The exporter needs real nesting. Making one parser serve both is how
Markdown editors end up with a parser nobody dares change.

Preview mode works at the glyph layer: syntax characters are given the `.null`
glyph property, which removes them from layout without touching the text. The
characters are still in the buffer, still saved to disk, and still there when the
caret reaches them. Nothing is ever rewritten to make the view look right.

## Things it deliberately doesn't do

No vault, no graph, no backlinks, no sync, no plugins. Obsidian is good at that
and Doctor's job ends at the point where you decide something is worth keeping.

## Known rough edges

- Inline `<html>` in source is escaped on export apart from a small whitelist of
  formatting tags, so a document can't pull remote resources or run scripts just
  because you pressed Print.
- Reference-style links (`[text][ref]`) aren't resolved yet; they render literally.
- Footnotes are styled in the editor but printed as plain text.
