import SwiftUI
import SwiftData

/// One document, rendered. The `ReaderView` here is exactly the same one
/// `ContentView`'s old single-document screen used before the library
/// existed — nothing about the rendering path changed, only what feeds it.
struct DocumentDetailView: View {
    var document: Document
    @Environment(\.modelContext) private var context
    @State private var editing = false

    var body: some View {
        ReaderView(text: document.body)
            .navigationTitle(document.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { editing = true }
                }
            }
            .sheet(isPresented: $editing) {
                ComposeView(document: document)
            }
    }
}

#Preview {
    let container = Persistence.makeInMemoryContainer()
    let document = Document(title: "Preview", body: ContentView.sample)
    container.mainContext.insert(document)
    return NavigationStack {
        DocumentDetailView(document: document)
    }
    .modelContainer(container)
}
