import Foundation
import Observation

/// The persisted half of `ReaderSettings` — UserDefaults-backed, shared app
/// wide, the iOS equivalent of what `AppSettings` is to the Mac app (minus
/// everything here that's Mac-only: the menu bar, the vault path, spell
/// check). One instance, read by every open document.
@Observable
final class ReaderPreferences {
    static let shared = ReaderPreferences()

    private enum Key {
        static let font = "reader.font"
        static let previewFontSize = "reader.previewFontSize"
    }

    private let defaults: UserDefaults

    var font: ReaderFont {
        didSet { defaults.set(font.rawValue, forKey: Key.font) }
    }

    var previewFontSize: Double {
        didSet { defaults.set(previewFontSize, forKey: Key.previewFontSize) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        font = (defaults.string(forKey: Key.font)).flatMap(ReaderFont.init) ?? .sans
        let storedSize = defaults.object(forKey: Key.previewFontSize) as? Double
        previewFontSize = storedSize ?? 18
    }

    var settings: ReaderSettings {
        ReaderSettings(font: font, previewFontSize: previewFontSize)
    }
}
