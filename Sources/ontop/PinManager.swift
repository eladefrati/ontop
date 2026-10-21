import AppKit
import ScreenCaptureKit

/// Owns every pin and decides, on each focus change, which mirrors are shown.
@MainActor
final class PinManager {
    private var slots = PinSlots<Pin>()
    /// The last app other than ontop that was frontmost. Used when the user picks "pin
    /// frontmost window" from our own menu, which may have activated ontop.
    private(set) var lastFrontmostPID: pid_t?

    var onChange: (() -> Void)?

    init() {
        lastFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(applicationTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceChanged(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
    }

    var followsDesktops: Bool {
        get { Settings.followsDesktops }
        set {
            Settings.followsDesktops = newValue
            for pin in slots.values {
                pin.setFollowsDesktops(newValue)
                pin.evaluate(frontmostPID: lastFrontmostPID)
            }
        }
    }

    var hasPins: Bool { !slots.isEmpty }

    func isPinned(_ id: CGWindowID) -> Bool { slots.contains(id) }

    /// Pin if unpinned, unpin if pinned, cancel if still resolving: two toggles in a row,
    /// however close, leave the window as it was.
    func toggle(_ id: CGWindowID) {
        switch slots.toggle(id) {
        case .resolve(let ticket):
            Task { await pin(ticket) }
            onChange?()
        case .cancelled:
            Log.app.info("pin cancelled (\(id))")
            onChange?()
        case .unpinned(let pin):
            unpinned(pin)
        }
    }

    func pinFrontmostWindow() {
        guard let pid = lastFrontmostPID, let window = WindowList.frontWindow(ofPID: pid) else {
            Log.app.info("no frontmost window to pin")
            return
        }
        toggle(window.id)
    }

    /// One await, then a synchronous build and store. The mirror, stream and AX observer
    /// are created only after the ticket is known to be current, and no await comes between
    /// that check and the store.
    private func pin(_ ticket: PinSlots<Pin>.Ticket) async {
        let id = ticket.windowID
        let windows: [SCWindow]?
        do {
            windows = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true).windows
        } catch {
            Log.app.error("shareable content: \(error.localizedDescription)")
            windows = nil
        }
        guard slots.isCurrent(ticket) else { return }
        guard let windows, let pin = makePin(id, from: windows) else {
            _ = slots.remove(id)
            onChange?()
            return
        }
        slots.store(pin, for: ticket)
        Log.app.info("pinned \(pin.target.scWindow.title ?? "") (\(id))")
        pin.evaluate(frontmostPID: lastFrontmostPID)
        onChange?()
    }

    private func makePin(_ id: CGWindowID, from windows: [SCWindow]) -> Pin? {
        guard let window = windows.first(where: { $0.windowID == id }) else {
            Log.app.error("window \(id) is no longer on screen")
            return nil
        }
        guard let target = TargetWindow(scWindow: window) else {
            Log.app.error("could not track window \(id)")
            return nil
        }
        let pin = Pin(target: target)
        pin.onGone = { [weak self] in
            _ = self?.slots.remove(id)
            self?.onChange?()
        }
        return pin
    }

    func unpin(_ id: CGWindowID) {
        guard let pin = slots.remove(id) else { return }
        unpinned(pin)
    }

    func unpinAll() {
        for pin in slots.removeAll() { unpinned(pin) }
    }

    private func unpinned(_ pin: Pin) {
        pin.unpin()
        Log.app.info("unpinned \(pin.target.scWindow.windowID)")
        onChange?()
    }

    @objc private func applicationActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        // ontop taking focus (its own menu) changes nothing about what the user is looking at.
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        lastFrontmostPID = pid
        for pin in slots.values { pin.evaluate(frontmostPID: pid) }
    }

    @objc private func activeSpaceChanged(_ note: Notification) {
        for pin in slots.values { pin.evaluate(frontmostPID: lastFrontmostPID) }
    }

    @objc private func applicationTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        for id in slots.ids(where: { $0.target.pid == app.processIdentifier }) { unpin(id) }
    }
}
