import AppKit
import ScreenCaptureKit

/// Why a pin could not be made, or ended without the user asking. The status menu beeps and
/// shows `message` as its first line until the next pin or unpin.
enum PinFailure: Error, Equatable {
    /// The front app has no window ontop can pin (hotkey or "Pin Frontmost Window").
    case noWindow
    /// Its app marks the window as not capturable.
    case notCapturable(title: String)
    /// The window left the screen before ScreenCaptureKit listed it.
    case notOnScreen(title: String)
    /// No standard Accessibility window matches it, so its moves can't be followed.
    case notAccessible(title: String)
    /// ScreenCaptureKit gave no window list, typically because Screen Recording was turned off.
    case contentUnavailable(title: String)
    /// The capture failed `MirrorStream.maxFailures + 1` times in a row and the pin ended.
    case captureStopped(title: String)
    /// A click on the mirror was dropped: the window did not come to the front in time.
    case clickNotDelivered(title: String)

    var message: String {
        switch self {
        case .noWindow: "Nothing to pin: the front app has no window ontop can pin"
        case .notCapturable(let title): "Could not pin \u{201C}\(title)\u{201D}: its app does not allow it to be captured"
        case .notOnScreen(let title): "Could not pin \u{201C}\(title)\u{201D}: it is no longer on screen"
        case .notAccessible(let title): "Could not pin \u{201C}\(title)\u{201D}: ontop can't follow it through Accessibility"
        case .contentUnavailable(let title): "Could not pin \u{201C}\(title)\u{201D}: no window list from macOS; check Screen Recording"
        case .captureStopped(let title): "\u{201C}\(title)\u{201D} is no longer pinned: macOS stopped capturing it"
        case .clickNotDelivered(let title): "Could not click in \u{201C}\(title)\u{201D}: it did not come to the front"
        }
    }
}

/// What every pin reads to place and show its mirror. Built only by PinManager.
struct PinContext {
    /// The app the user is looking at; never ontop itself.
    var frontmostPID: pid_t?
    var followsDesktops: Bool
}

/// Owns every pin and decides, on each focus change, which mirrors are shown.
@MainActor
final class PinManager {
    private var slots = PinSlots<Pin>()
    /// Finds the window among ScreenCaptureKit's: the one await between a toggle and its store.
    /// Tests pass their own, so they run the real toggle without ScreenCaptureKit.
    private let lookup: @MainActor (WindowInfo) async -> Result<SCWindow, PinFailure>
    /// The last app other than ontop that was frontmost. The only frontmost source: the
    /// hotkey and "Pin Frontmost Window" (which may have activated ontop) find their window
    /// with it, and every pin reads it through `context`.
    private var frontmostPID: pid_t?

    var onChange: (() -> Void)?
    /// Why the last pin failed or ended, until the next toggle or Unpin All.
    private(set) var failure: PinFailure?
    /// A pin failed or ended without the user asking.
    var onFailure: (() -> Void)?

    init(lookup: @escaping @MainActor (WindowInfo) async -> Result<SCWindow, PinFailure> = PinManager.shareableWindow) {
        self.lookup = lookup
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
            for pin in slots.values { pin.evaluate() }
        }
    }

    var hasPins: Bool { !slots.isEmpty }

    func isPinned(_ id: CGWindowID) -> Bool { slots.contains(id) }

    /// Pin if unpinned, unpin if pinned, cancel if still resolving: two toggles in a row,
    /// however close, leave the window as it was.
    func toggle(_ window: WindowInfo) {
        failure = nil
        switch slots.toggle(window.id) {
        case .resolve(let ticket): Task { await pin(ticket, window) }
        case .cancelled: Log.app.info("pin cancelled (\(window.id))")
        case .unpinned(let pin): finish(pin, .user)
        }
        onChange?()
    }

    func pinFrontmostWindow() {
        guard let pid = frontmostPID, let window = WindowList.frontWindow(ofPID: pid) else {
            Log.app.info("no frontmost window to pin")
            report(.noWindow)
            return
        }
        guard window.isCapturable else {
            Log.app.info("front window \(window.id) can't be captured")
            report(.notCapturable(title: window.title))
            return
        }
        toggle(window)
    }

    /// One await, then a synchronous build and store. The mirror, stream and AX observer
    /// are created only after the ticket is known to be current, and no await comes between
    /// that check and the store.
    private func pin(_ ticket: PinSlots<Pin>.Ticket, _ window: WindowInfo) async {
        let found = await lookup(window)
        // Toggled off meanwhile: build nothing and say nothing.
        guard slots.isCurrent(ticket) else { return }
        do throws(PinFailure) {
            let pin = try makePin(window, found.get())
            slots.store(pin, for: ticket)
            Log.app.info("pinned \(window.title) (\(window.id))")
            pin.evaluate()
        } catch {
            _ = slots.remove(window.id)
            report(error)
        }
        onChange?()
    }

    /// The window as ScreenCaptureKit lists it among the on-screen windows.
    static func shareableWindow(_ window: WindowInfo) async -> Result<SCWindow, PinFailure> {
        do {
            let windows = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true).windows
            guard let found = windows.first(where: { $0.windowID == window.id }) else {
                Log.app.error("window \(window.id) is no longer on screen")
                return .failure(.notOnScreen(title: window.title))
            }
            return .success(found)
        } catch {
            Log.app.error("shareable content: \(error.localizedDescription)")
            return .failure(.contentUnavailable(title: window.title))
        }
    }

    private func makePin(_ window: WindowInfo, _ scWindow: SCWindow) throws(PinFailure) -> Pin {
        let id = window.id
        guard let target = TargetWindow(windowID: id, pid: window.pid, frame: scWindow.frame, title: scWindow.title) else {
            Log.app.error("could not track window \(id)")
            throw .notAccessible(title: window.title)
        }
        return Pin(target: target,
                   title: window.title,
                   capture: WindowCapture(window: scWindow),
                   context: { [unowned self] in context },
                   report: { [weak self] failure in self?.report(failure) },
                   onEnd: { [weak self] reason in self?.remove(id, reason) })
    }

    func unpinAll() {
        failure = nil
        for pin in slots.removeAll() { finish(pin, .user) }
        onChange?()
    }

    private var context: PinContext {
        PinContext(frontmostPID: frontmostPID, followsDesktops: Settings.followsDesktops)
    }

    /// A pin asked to end, or its app quit.
    private func remove(_ id: CGWindowID, _ reason: Pin.EndReason) {
        guard let pin = slots.remove(id) else { return }
        finish(pin, reason)
        onChange?()
    }

    /// The one place a failure reaches the user.
    private func report(_ failure: PinFailure) {
        self.failure = failure
        onFailure?()
    }

    /// The single teardown path: every pin ends here, whatever ended it.
    private func finish(_ pin: Pin, _ reason: Pin.EndReason) {
        pin.end()
        let id = pin.target.windowID
        switch reason {
        case .user: Log.app.info("unpinned \(id)")
        case .windowGone: Log.app.info("unpinned \(id): window closed or minimized")
        case .appQuit: Log.app.info("unpinned \(id): app quit")
        case .captureFailed:
            Log.app.info("unpinned \(id): capture failed")
            report(.captureStopped(title: pin.title))
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
