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

    func toggle(_ id: CGWindowID) {
        switch slots.toggle(id) {
        case .resolve(let ticket): Task { await pin(ticket) }
        case .unpinned(let pin): unpinned(pin)
        }
    }

    func pinFrontmostWindow() {
        guard let pid = lastFrontmostPID, let window = WindowList.frontWindow(ofPID: pid) else {
            Log.app.info("no frontmost window to pin")
            return
        }
        toggle(window.id)
    }

    private func pin(_ ticket: PinSlots<Pin>.Ticket) async {
        let id = ticket.windowID
        guard slots.isCurrent(ticket) else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                Log.app.error("window \(id) is no longer on screen")
                return
            }
            guard let target = TargetWindow(scWindow: window) else {
                Log.app.error("could not track window \(id)")
                return
            }
            let pin = Pin(target: target)
            pin.onGone = { [weak self] in
                _ = self?.slots.remove(id)
                self?.onChange?()
            }
            slots.store(pin, for: ticket)
            Log.app.info("pinned \(window.title ?? "") (\(id))")
            pin.evaluate(frontmostPID: lastFrontmostPID)
            onChange?()
        } catch {
            Log.app.error("shareable content: \(error.localizedDescription)")
        }
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
