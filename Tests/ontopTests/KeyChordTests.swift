import AppKit
import Carbon
import Testing
@testable import ontop

struct KeyChordTests {
    private func chord(_ flags: NSEvent.ModifierFlags) -> KeyChord {
        KeyChord(keyCode: UInt32(kVK_ANSI_P), modifiers: flags.rawValue, keyEquivalent: "p", display: "")
    }

    @Test func controlOptionMapsToCarbonControlAndOption() {
        #expect(chord([.control, .option]).carbonModifiers == UInt32(controlKey | optionKey))
    }

    @Test func shiftCommandMapsToCarbonShiftAndCommand() {
        #expect(chord([.shift, .command]).carbonModifiers == UInt32(shiftKey | cmdKey))
    }

    @Test func noModifiersMapToZero() {
        #expect(chord([]).carbonModifiers == 0)
    }
}
