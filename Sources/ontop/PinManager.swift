import AppKit
import ScreenCaptureKit

/// What every pin reads to show its mirror. Built only by PinManager.
struct PinContext {
    /// The app the user is looking at; never ontop itself.
    var frontmostPID: pid_t?
}

/// Owns every pin and decides, on each focus change, which mirrors are shown.
@MainActor
final class PinManager {
    private var slots = PinSlots<Pin>()
    /// The last app other than ontop that was frontmost. The only frontmost source: the
    /// hotkey and "Pin Frontmost Window" (which may have activated ontop) find their window
    /// with it, and every pin reads it through `context`.
    private var frontmostPID: pid_t?

    var onChange: (() -> Void)?

    init() {
        // An accessory app never owns the menu bar, so if ontop is frontmost at launch the
        // menu bar's owner is the app the user was in.
        let own = ProcessInfo.processInfo.processIdentifier
        frontmostPID = [NSWorkspace.shared.frontmostApplication, NSWorkspace.shared.menuBarOwningApplication]
            .compactMap { $0?.processIdentifier }
            .first { $0 != own }
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
                pin.evaluate()
            }
        }
    }

    var hasPins: Bool { !slots.isEmpty }

    func isPinned(_ id: CGWindowID) -> Bool { slots.contains(id) }

    /// Pin if unpinned, unpin if pinned, cancel if still resolving: two toggles in a row,
    /// however close, leave the window as it was.
    func toggle(_ id: CGWindowID) {
        switch slots.toggle(id) {
        case .resolve(let ticket): Task { await pin(ticket) }
        case .cancelled: Log.app.info("pin cancelled (\(id))")
        case .unpinned(let pin): finish(pin, .user)
        }
        onChange?()
    }

    func pinFrontmostWindow() {
        guard let pid = frontmostPID, let window = WindowList.frontWindow(ofPID: pid) else {
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
        pin.evaluate()
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
        return Pin(target: target,
                   context: { [unowned self] in context },
                   onEnd: { [weak self] reason in self?.remove(id, reason) })
    }

    func unpinAll() {
        for pin in slots.removeAll() { finish(pin, .user) }
        onChange?()
    }

    private var context: PinContext {
        PinContext(frontmostPID: frontmostPID)
    }

    /// A pin asked to end, or its app quit.
    private func remove(_ id: CGWindowID, _ reason: Pin.EndReason) {
        guard let pin = slots.remove(id) else { return }
        finish(pin, reason)
        onChange?()
    }

    /// The single teardown path: every pin ends here, whatever ended it.
    private func finish(_ pin: Pin, _ reason: Pin.EndReason) {
        pin.end()
        let id = pin.target.scWindow.windowID
        switch reason {
        case .user: Log.app.info("unpinned \(id)")
        case .windowGone: Log.app.info("unpinned \(id): window closed or minimized")
        case .appQuit: Log.app.info("unpinned \(id): app quit")
        case .captureFailed: Log.app.info("unpinned \(id): capture failed")
        }
    }

    @objc private func applicationActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        // ontop taking focus (its own menu) changes nothing about what the user is looking at.
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        frontmostPID = pid
        for pin in slots.values { pin.evaluate() }
    }

    @objc private func activeSpaceChanged(_ note: Notification) {
        for pin in slots.values { pin.evaluate() }
    }

    @objc private func applicationTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        for id in slots.ids(where: { $0.target.pid == app.processIdentifier }) { remove(id, .appQuit) }
    }
}
