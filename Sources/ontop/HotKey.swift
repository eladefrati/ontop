import AppKit
import Carbon

/// The system-wide shortcut for Pin Frontmost Window, through Carbon's hot key API, which
/// needs no permission and fires regardless of which app is frontmost. Owns the chord: the
/// only reader and writer of `Settings.chord`.
@MainActor
final class HotKey {
    private static let signature: OSType = 0x6F6E7470 // "ontp"

    enum RegistrationError: Error {
        case inUse
        case failed(OSStatus)
    }

    /// The saved chord, registered or not.
    private(set) var chord: KeyChord

    private enum State {
        case registered(EventHotKeyRef)
        case failed(RegistrationError)
    }

    private var state: State
    private var handlerRef: EventHandlerRef?
    private let onPress: @MainActor () -> Void
    /// Each registration gets a fresh id, so the old and new chords can both be registered
    /// for the instant of a change.
    private var lastID: UInt32 = 1

    /// Registers the saved chord. A failure is logged, not thrown: the app runs without the
    /// shortcut.
    init(onPress: @escaping @MainActor () -> Void) {
        self.onPress = onPress
        chord = Settings.chord
        switch Self.register(chord, id: lastID) {
        case .success(let ref):
            state = .registered(ref)
        case .failure(let error):
            state = .failed(error)
            Log.app.error("hotkey \(self.chord.display) unavailable: \(String(describing: error))")
        }
        let callback: EventHandlerUPP = { _, _, refcon in
            guard let refcon else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(refcon).takeUnretainedValue()
            Log.app.info("hotkey pressed")
            // Carbon dispatches application events on the main run loop.
            MainActor.assumeIsolated { hotKey.onPress() }
            return noErr
        }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, refcon, &handlerRef)
        if status != noErr {
            Log.app.error("InstallEventHandler failed: \(status)")
        }
    }

    /// Registers `chord`, then releases the previous registration, then saves `chord`. On
    /// failure nothing changes: the previous chord stays registered and saved, so a caller
    /// has nothing to roll back.
    func change(to chord: KeyChord) throws(RegistrationError) {
        if chord == self.chord, case .registered = state { return }
        lastID += 1
        let new = try Self.register(chord, id: lastID).get()
        if case .registered(let old) = state { UnregisterEventHotKey(old) }
        state = .registered(new)
        self.chord = chord
        Settings.chord = chord
    }

    private static func register(_ chord: KeyChord, id: UInt32) -> Result<EventHotKeyRef, RegistrationError> {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(chord.keyCode, chord.carbonModifiers, EventHotKeyID(signature: signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        switch status {
        case noErr:
            guard let ref else { return .failure(.failed(status)) }
            Log.app.info("hotkey registered: \(chord.display)")
            return .success(ref)
        case OSStatus(eventHotKeyExistsErr):
            return .failure(.inUse)
        default:
            return .failure(.failed(status))
        }
    }
}
