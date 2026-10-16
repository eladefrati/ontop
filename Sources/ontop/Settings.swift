import Foundation

/// Persisted preferences.
enum Settings {
    private static let chordKey = "chord"
    private static let followsDesktopsKey = "followsDesktops"

    /// Whether mirrors appear on every desktop or stay on the desktop of their window.
    static var followsDesktops: Bool {
        get { UserDefaults.standard.bool(forKey: followsDesktopsKey) }
        set { UserDefaults.standard.set(newValue, forKey: followsDesktopsKey) }
    }

    static var chord: KeyChord {
        get {
            guard let data = UserDefaults.standard.data(forKey: chordKey),
                  let chord = try? JSONDecoder().decode(KeyChord.self, from: data)
            else { return .default }
            return chord
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: chordKey)
        }
    }
}
