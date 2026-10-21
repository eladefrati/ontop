// The pure decisions behind a Pin. Pin.swift executes them; the tests drive them directly.

enum MirrorVisibility {
    /// Hidden while the real window is what the user sees: its app is frontmost and it is
    /// that app's focused window. Also hidden while the mirror's desktop is not the active
    /// one, since nobody could see it and the stream would run for nothing. Shown otherwise.
    static func wanted(realWindowInFront: Bool, onActiveDesktop: Bool) -> Bool {
        !realWindowInFront && onActiveDesktop
    }
}
