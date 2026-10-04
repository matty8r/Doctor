import SwiftUI

/// App-wide reading preferences — small on purpose. The Mac app's Settings
/// has a full font-family picker, vault paths, spell check; none of that
/// has an iOS equivalent yet, or needs one for what this screen is for.
struct ReaderSettingsView: View {
    @Bindable var preferences: ReaderPreferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Font") {
                    Picker("Font", selection: $preferences.font) {
                        ForEach(ReaderFont.allCases) { font in
                            Text(font.title).tag(font)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    HStack {
                        Text("Size")
                        Slider(value: $preferences.previewFontSize, in: 14...26, step: 1)
                        Text("\(Int(preferences.previewFontSize))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                    }
                }

                Section {
                    Text(ReaderSettingsView.sample)
                        .font(.system(size: preferences.previewFontSize, design: preferences.font == .serif ? .serif : .default))
                } header: {
                    Text("Preview")
                }
            }
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    static let sample = "The quick brown fox jumps over the lazy dog."
}

#Preview {
    ReaderSettingsView(preferences: ReaderPreferences.shared)
}
