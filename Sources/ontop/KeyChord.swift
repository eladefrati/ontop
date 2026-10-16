import AppKit
import Carbon

/// A keyboard shortcut: a key plus modifier keys pressed together.
struct KeyChord: Codable, Equatable {
    /// Hardware key code, layout-independent (kVK_* constants).
    var keyCode: UInt32
    /// NSEvent.ModifierFlags raw value, device-independent bits only.
    var modifiers: UInt
    /// The key's character for NSMenuItem.keyEquivalent, e.g. "p" or a function-key scalar.
    var keyEquivalent: String
    /// Human-readable form, e.g. "⌃⌥P".
    var display: String

    init(keyCode: UInt32, modifiers: UInt, keyEquivalent: String, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyEquivalent = keyEquivalent
        self.display = display
    }

    static let `default` = KeyChord(
        keyCode: UInt32(kVK_ANSI_P),
        modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue,
        keyEquivalent: "p",
        display: "⌃⌥P"
    )

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        return mask
    }

    /// Builds a chord from a key event, or nil when the event is not usable as a global
    /// shortcut: it needs at least one of Control, Option or Command and a nameable key.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard !flags.intersection([.control, .option, .command]).isEmpty else { return nil }
        guard let name = Self.keyName(for: event), let equivalent = event.charactersIgnoringModifiers else { return nil }
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        self.init(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue, keyEquivalent: equivalent.lowercased(), display: symbols + name)
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func keyName(for event: NSEvent) -> String? {
        if let special = specialKeys[Int(event.keyCode)] { return special }
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1,
              let scalar = chars.unicodeScalars.first,
              scalar.isASCII, scalar.value > 0x20, scalar.value < 0x7f
        else { return nil }
        return chars.uppercased()
    }
}
