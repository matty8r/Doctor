import SwiftUI
import SwiftData
import DoctorLibrary
import DoctorEditorKit

/// One document — title and body both editable in place, no separate
/// compose screen. `DocumentEditor` is the same engine `ContentView`'s old
/// single-document screen proved on real hardware before the library
/// existed; only what feeds it, and whether it's editable, changed.
struct DocumentDetailView: View {
    @Bindable var document: Document
    @Environment(\.modelContext) private var context
    @State private var mode: EditorMode = .preview
    private let preferences = ReaderPreferences.shared

    var body: some View {
        VStack(spacing: 0) {
            TextField("Untitled", text: $document.title)
                .font(.title2.bold())
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)
            DocumentEditor(text: $document.body, mode: mode, settings: preferences.settings)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $mode) {
                    ForEach(EditorMode.allCases) { mode in
                        Image(systemName: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
        }
        // Edits land straight in the SwiftData model as they're typed —
        // SwiftData's own autosave covers the ordinary case, this is the
        // explicit save for the moment that matters most: leaving the
        // document. modifiedAt updates here too, on leaving rather than on
        // every keystroke, so the library's sort order doesn't reshuffle
        // under someone mid-sentence.
        .onDisappear {
            document.touch()
            try? context.save()
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
