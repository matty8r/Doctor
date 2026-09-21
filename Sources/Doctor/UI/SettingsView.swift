import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            EditorSettings()
                .tabItem { Label("Editor", systemImage: "text.alignleft") }
            ObsidianSettings()
                .tabItem { Label("Obsidian", systemImage: "square.stack.3d.up") }
        }
        .environmentObject(settings)
        .frame(width: 480)
        .padding(18)
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Picker("Theme", selection: $settings.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }

            Picker("Open documents in", selection: $settings.defaultMode) {
                ForEach(EditorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Divider().padding(.vertical, 4)

            Toggle("Hide Markdown syntax in Preview", isOn: $settings.hideSyntax)
            Text("Punctuation reappears on the line you're editing, so you can always see what you're changing.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Editor

private struct EditorSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Preview") {
                FontPicker(title: "Font", selection: $settings.previewFontName, monospacedOnly: false)
                Stepper(value: $settings.previewFontSize, in: 10...28, step: 0.5) {
                    Text("Size: \(settings.previewFontSize, specifier: "%.1f") pt")
                }
                Slider(value: $settings.contentWidth, in: 480...1200, step: 20) {
                    Text("Column width")
                } minimumValueLabel: {
                    Text("Narrow").font(.system(size: 10))
                } maximumValueLabel: {
                    Text("Wide").font(.system(size: 10))
                }
            }

            Section("Source") {
                FontPicker(title: "Font", selection: $settings.sourceFontName, monospacedOnly: true)
                Stepper(value: $settings.sourceFontSize, in: 9...24, step: 0.5) {
                    Text("Size: \(settings.sourceFontSize, specifier: "%.1f") pt")
                }
            }

            Section("Typing") {
                Slider(value: $settings.lineSpacing, in: 1.0...2.0, step: 0.05) {
                    Text("Line spacing: \(settings.lineSpacing, specifier: "%.2f")")
                }
                Toggle("Continue lists and quotes on Return", isOn: $settings.smartLists)
                Toggle("Check spelling while typing", isOn: $settings.continuousSpellCheck)
            }
        }
        .formStyle(.grouped)
    }
}

private struct FontPicker: View {
    let title: String
    @Binding var selection: String
    let monospacedOnly: Bool

    var body: some View {
        Picker(title, selection: $selection) {
            Text("System").tag("")
            ForEach(families, id: \.self) { family in
                Text(family).tag(family)
            }
        }
    }

    private var families: [String] {
        let all = NSFontManager.shared.availableFontFamilies.sorted()
        guard monospacedOnly else { return all }
        // Cheap heuristic, but it beats scrolling past 300 proportional faces.
        let known = ["Menlo", "Monaco", "Courier", "SF Mono", "Andale Mono", "PT Mono",
                     "Consolas", "Inconsolata", "Fira", "JetBrains", "IBM Plex Mono",
                     "Source Code", "Roboto Mono", "Ubuntu Mono", "Hack", "Iosevka",
                     "Cascadia", "Monaspace", "Berkeley"]
        return all.filter { family in
            known.contains { family.localizedCaseInsensitiveContains($0) }
                || family.localizedCaseInsensitiveContains("mono")
        }
    }
}

// MARK: - Obsidian

private struct ObsidianSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Vault") {
                HStack {
                    Text("Folder")
                    Spacer()
                    Text(displayPath)
                        .foregroundStyle(settings.vaultPath.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Button("Choose…", action: chooseVault)
                }

                TextField("Vault name", text: $settings.vaultName, prompt: Text(derivedName))
                Text("Obsidian identifies vaults by name. Leave this blank to use the folder's name, which is usually right.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Filing") {
                TextField("Subfolder", text: $settings.vaultFolder, prompt: Text("Vault root"))
                Text("Documents you send are copied here. The original file stays where it is.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Open the note in Obsidian afterwards", isOn: $settings.revealAfterSend)
            }
        }
        .formStyle(.grouped)
    }

    private var displayPath: String {
        settings.vaultPath.isEmpty
            ? "Not set"
            : settings.vaultPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var derivedName: String {
        settings.vaultPath.isEmpty
            ? "My Vault"
            : URL(fileURLWithPath: settings.vaultPath).lastPathComponent
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose your Obsidian vault folder"
        panel.prompt = "Use Vault"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.vaultPath = url.path
    }
}
