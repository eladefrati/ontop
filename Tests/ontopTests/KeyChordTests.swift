import AppKit
import Carbon
import Testing
@testable import ontop

@MainActor
struct KeyChordTests {
    private let latin: KeyChord.Layout = { $0 == UInt32(kVK_ANSI_P) ? "p" : nil }

    private func chord(_ flags: NSEvent.ModifierFlags) -> KeyChord {
        KeyChord(keyCode: UInt32(kVK_ANSI_P), modifiers: flags)
    }

    private func keyDown(_ keyCode: Int, _ flags: NSEvent.ModifierFlags, typing characters: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                      context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                      isARepeat: false, keyCode: UInt16(keyCode)))
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

    @Test func recordsALetterWhileANonLatinLayoutIsActive() throws {
        let recorded = try #require(KeyChord(event: keyDown(kVK_ANSI_P, [.control, .option], typing: "\u{5E4}"), layout: latin))
        #expect(recorded == .default)
        #expect(recorded.describe(layout: latin) == "⌃⌥P")
    }

    @Test func shiftAloneIsNotAShortcut() throws {
        #expect(KeyChord(event: try keyDown(kVK_ANSI_P, [.shift], typing: "P"), layout: latin) == nil)
    }

    @Test func aKeyWithNoNameIsNotAShortcut() throws {
        #expect(KeyChord(event: try keyDown(kVK_ANSI_Q, [.control], typing: "q"), layout: latin) == nil)
    }

    @Test func capsLockAndFunctionAreLeftOut() throws {
        let recorded = try #require(KeyChord(event: keyDown(kVK_ANSI_P, [.control, .option, .capsLock, .function], typing: "p"),
                                             layout: latin))
        #expect(recorded.flags == [.control, .option])
    }

    @Test func modifiersAreNamedInAFixedOrder() {
        #expect(chord([.command, .shift, .option, .control]).describe(layout: latin) == "⌃⌥⇧⌘P")
    }

    @Test func aFunctionKeyIsNamedByTheTableWhateverTheLayout() {
        let f5 = KeyChord(keyCode: UInt32(kVK_F5), modifiers: [.command])
        #expect(f5.describe(layout: { _ in "x" }) == "⌘F5")
        #expect(f5.keyEquivalent == String(Character(UnicodeScalar(UInt32(NSF5FunctionKey))!)))
    }

    @Test func spaceIsNamedSpace() {
        #expect(KeyChord.keyName(UInt32(kVK_Space), layout: { _ in " " }) == "Space")
    }

    @Test func aChordSavedWithItsLabelsStillLoads() throws {
        let saved = #"{"keyCode":35,"modifiers":786432,"keyEquivalent":"p","display":"⌃⌥P"}"#
        #expect(try JSONDecoder().decode(KeyChord.self, from: Data(saved.utf8)) == .default)
    }

    @Test func aChordSavesItsKeyAndModifiersOnly() throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(KeyChord.default)) as? [String: Any]
        #expect(object.map { Set($0.keys) } == ["keyCode", "modifiers"])
    }
}
