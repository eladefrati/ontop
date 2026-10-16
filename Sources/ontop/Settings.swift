import Foundation

/// Persisted preferences.
enum Settings {
    private static let chordKey = "chord"

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
