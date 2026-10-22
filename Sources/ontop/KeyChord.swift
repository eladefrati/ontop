import AppKit
import Carbon

/// A keyboard shortcut: a key plus modifier keys pressed together. Stores only what identifies
/// the chord; its label and menu key equivalent come from the keyboard layout when read.
struct KeyChord: Codable, Equatable {
    /// Hardware key code, layout-independent (kVK_* constants).
    var keyCode: UInt32
    /// NSEvent.ModifierFlags raw value: Control, Option, Shift and Command only.
    var modifiers: UInt

    // Chords saved before also carry "keyEquivalent" and "display". The synthesized decoder
    // ignores keys it doesn't know, so they still load.

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.control, .option, .shift, .command]).rawValue
    }

    static let `default` = KeyChord(keyCode: UInt32(kVK_ANSI_P), modifiers: [.control, .option])

    /// The character a key code types with no modifiers. Injected so tests don't depend on the
    /// Mac's keyboard layout.
    typealias Layout = @MainActor (UInt32) -> Character?

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
    /// shortcut: it needs at least one of Control, Option or Command and a nameable key. Reads
    /// the key code, never the typed characters, so letter chords record under any layout.
    @MainActor
    init?(event: NSEvent, layout: Layout = KeyChord.asciiLayout) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard !flags.intersection([.control, .option, .command]).isEmpty,
              Self.keyName(UInt32(event.keyCode), layout: layout) != nil
        else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: flags)
    }

    /// Human-readable form, e.g. "⌃⌥P".
    @MainActor
    var display: String { describe(layout: Self.asciiLayout) }

    /// The key's character for NSMenuItem.keyEquivalent, e.g. "p" or a function-key scalar.
    @MainActor
    var keyEquivalent: String {
        if let special = Self.specialKeys[Int(keyCode)] { return special.equivalent }
        return Self.asciiLayout(keyCode).map { String($0).lowercased() } ?? ""
    }

    /// Modifier symbols in ⌃⌥⇧⌘ order, then the key's name.
    @MainActor
    func describe(layout: Layout) -> String {
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols + (Self.keyName(keyCode, layout: layout) ?? "?")
    }

    /// The special-key table first, else the layout's character uppercased when it is
    /// printable ASCII.
    @MainActor
    static func keyName(_ keyCode: UInt32, layout: Layout) -> String? {
        if let special = specialKeys[Int(keyCode)] { return special.name }
        guard let character = layout(keyCode), character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first, scalar.value > 0x20, scalar.value < 0x7f
        else { return nil }
        return character.uppercased()
    }

    /// Label and menu key equivalent per special key, so the two can't disagree.
    static let specialKeys: [Int: (name: String, equivalent: String)] = [
        kVK_Space: ("Space", " "), kVK_Return: ("↩", "\r"), kVK_Tab: ("⇥", "\t"), kVK_Delete: ("⌫", "\u{8}"),
        kVK_ForwardDelete: ("⌦", function(NSDeleteFunctionKey)),
        kVK_LeftArrow: ("←", function(NSLeftArrowFunctionKey)), kVK_RightArrow: ("→", function(NSRightArrowFunctionKey)),
        kVK_UpArrow: ("↑", function(NSUpArrowFunctionKey)), kVK_DownArrow: ("↓", function(NSDownArrowFunctionKey)),
        kVK_Home: ("↖", function(NSHomeFunctionKey)), kVK_End: ("↘", function(NSEndFunctionKey)),
        kVK_PageUp: ("⇞", function(NSPageUpFunctionKey)), kVK_PageDown: ("⇟", function(NSPageDownFunctionKey)),
        kVK_F1: ("F1", function(NSF1FunctionKey)), kVK_F2: ("F2", function(NSF2FunctionKey)),
        kVK_F3: ("F3", function(NSF3FunctionKey)), kVK_F4: ("F4", function(NSF4FunctionKey)),
        kVK_F5: ("F5", function(NSF5FunctionKey)), kVK_F6: ("F6", function(NSF6FunctionKey)),
        kVK_F7: ("F7", function(NSF7FunctionKey)), kVK_F8: ("F8", function(NSF8FunctionKey)),
        kVK_F9: ("F9", function(NSF9FunctionKey)), kVK_F10: ("F10", function(NSF10FunctionKey)),
        kVK_F11: ("F11", function(NSF11FunctionKey)), kVK_F12: ("F12", function(NSF12FunctionKey)),
    ]

    private static func function(_ key: Int) -> String {
        String(Character(UnicodeScalar(UInt32(key))!))
    }

    /// The character `keyCode` types with no modifiers in the current ASCII-capable layout:
    /// the layout macOS itself uses for shortcuts while a non-Latin one is active.
    @MainActor
    static func asciiLayout(_ keyCode: UInt32) -> Character? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { bytes in
            UCKeyTranslate(bytes.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self), UInt16(keyCode),
                           UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                           &deadKeyState, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: characters, count: length)
        return string.count == 1 ? string.first : nil
    }
}
