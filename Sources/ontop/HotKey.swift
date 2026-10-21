import AppKit
import Carbon

/// One system-wide shortcut registered through Carbon's hot key API, which needs no
/// permission and fires regardless of which app is frontmost.
@MainActor
final class HotKey {
    private static let signature: OSType = 0x6F6E7470 // "ontp"
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    var onPress: (() -> Void)?

    init() {
        let callback: EventHandlerUPP = { _, _, refcon in
            guard let refcon else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(refcon).takeUnretainedValue()
            Log.app.info("hotkey pressed")
            // Carbon dispatches application events on the main run loop.
            MainActor.assumeIsolated { hotKey.onPress?() }
            return noErr
        }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, refcon, &handlerRef)
        if status != noErr {
            Log.app.error("InstallEventHandler failed: \(status)")
        }
    }

    enum RegistrationError: Error {
        case inUse
        case failed(OSStatus)
    }

    /// Replaces the current registration. On failure the previous chord stays unregistered.
    func register(_ chord: KeyChord) throws(RegistrationError) {
        unregister()
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(chord.keyCode, chord.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        switch status {
        case noErr:
            hotKeyRef = ref
            Log.app.info("hotkey registered: \(chord.display)")
        case OSStatus(eventHotKeyExistsErr):
            throw .inUse
        default:
            throw .failed(status)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}
