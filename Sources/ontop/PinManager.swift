import AppKit
import ScreenCaptureKit

/// Owns every pin and decides, on each focus change, which mirrors are shown.
@MainActor
final class PinManager {
    private(set) var pins: [CGWindowID: Pin] = [:]
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
    }

    func isPinned(_ id: CGWindowID) -> Bool { pins[id] != nil }

    func toggle(_ id: CGWindowID) {
        if isPinned(id) { unpin(id) } else { Task { await pin(id) } }
    }

    func pinFrontmostWindow() {
        guard let pid = lastFrontmostPID, let window = WindowList.frontWindow(ofPID: pid) else {
            Log.app.info("no frontmost window to pin")
            return
        }
        toggle(window.id)
    }

    func pin(_ id: CGWindowID) async {
        guard pins[id] == nil else { return }
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
                self?.pins[id] = nil
                self?.onChange?()
            }
            pins[id] = pin
            Log.app.info("pinned \(window.title ?? "", privacy: .public) (\(id))")
            pin.evaluate(frontmostPID: lastFrontmostPID)
            onChange?()
        } catch {
            Log.app.error("shareable content: \(error.localizedDescription, privacy: .public)")
        }
    }

    func unpin(_ id: CGWindowID) {
        guard let pin = pins.removeValue(forKey: id) else { return }
        pin.unpin()
        Log.app.info("unpinned \(id)")
        onChange?()
    }

    func unpinAll() {
        for id in Array(pins.keys) { unpin(id) }
    }

    @objc private func applicationActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        // ontop taking focus (its own menu) changes nothing about what the user is looking at.
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        lastFrontmostPID = pid
        for pin in pins.values { pin.evaluate(frontmostPID: pid) }
    }

    @objc private func applicationTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        for (id, pin) in pins where pin.target.pid == app.processIdentifier { unpin(id) }
    }
}
