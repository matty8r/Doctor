import SwiftUI

/// The whole app, for now: one document, no library yet. This exists to prove
/// the shared engine actually renders on a real iOS text view — the CloudKit
/// library that replaces this is the next piece of work, not this one.
/// See ../../docs/ios.md.
struct ContentView: View {
    var body: some View {
        ReaderView(text: Self.sample)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Doctor")
    }

    /// Deliberately exercises the things that broke in 1.2/1.2.1 on macOS —
    /// a table, a fenced code block, a rule under a heading — so this same
    /// screen is a second, independent check that the port carried the fixes
    /// with it, not just the type signatures.
    static let sample = """
    # Doctor for iPhone

    This is the shared rendering engine — the same theme, the same syntax \
    highlighter, the same table layout — running on iOS for the first time.

    ---

    ## What it proves

    **Bold**, *italic*, and `inline code` all carry over, along with tables:

    | Piece | Status |
    | --- | --- |
    | Markdown engine | Free |
    | Theme + highlighter | Shimmed |
    | Layout manager | Ported |
    | Editing | Not yet — v1 reads |

    A fenced block, to check the panel sits snugly around it:

    ```swift
    let engine = "DoctorEditorKit"
    print("shared with \\(engine)")
    ```

    - A list item
    - Another, with **emphasis**
      - Nested one step

    > A blockquote, to check the bar renders where it should.
    """
}

#Preview {
    NavigationStack { ContentView() }
}
