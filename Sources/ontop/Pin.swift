import AppKit
import CoreGraphics

/// One pinned window: shows the mirror while another app is in front, hides it while the
/// pinned window is frontmost, and hands clicks on the mirror to the real window.
@MainActor
final class Pin: NSObject, NSWindowDelegate {
    let target: TargetWindow
    private let capture: WindowCapture
    private let mirror = MirrorWindow()
    private var shown = false
    private var awaitingFirstFrame = false
    private var restartAttempts = 0
    private static let maxRestartAttempts = 3
    /// Serializes start, stop and resize so a stop never races a start in flight.
    private var captureTask: Task<Void, Never>?

    var onGone: (() -> Void)?

    init(target: TargetWindow) {
        self.target = target
        self.capture = WindowCapture(window: target.scWindow)
        super.init()
        mirror.delegate = self
        // Ordered in now, invisible, so the mirror belongs to the desktop the window is on.
        mirror.setFrame(Geometry.appKitRect(fromCG: target.frame), display: false)
        mirror.orderFrontRegardless()
        capture.onFrame = { [weak self] surface in
            guard let self else { return }
            self.mirror.display(surface)
            if self.awaitingFirstFrame {
                self.awaitingFirstFrame = false
                self.mirror.setVisible(true)
            }
        }
        capture.onStopped = { [weak self] _ in self?.restartAfterStop() }
        mirror.onClick = { [weak self] point in self?.clicked(at: point) }
        target.onFrameChanged = { [weak self] frame in self?.frameChanged(frame) }
        target.onFocusChanged = { [weak self] in
            self?.evaluate(frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        }
        target.onGone = { [weak self] in
            self?.unpin()
            self?.onGone?()
        }
    }

    /// Hidden while the real window is what the user sees: its app is frontmost and it is
    /// that app's focused window. Also hidden while the mirror's desktop is not the active
    /// one, since nobody could see it and the stream would run for nothing. Shown otherwise.
    func evaluate(frontmostPID: pid_t?) {
        if frontmostPID == target.pid && target.isFocusedInApp {
            hide()
        } else if !mirror.isOnActiveSpace {
            hide()
        } else {
            show()
        }
    }

    func setFollowsDesktops(_ follows: Bool) {
        mirror.setFollowsDesktops(follows)
    }

    func show() {
        guard !shown else { return }
        shown = true
        let frame = Geometry.appKitRect(fromCG: target.frame)
        mirror.setFrame(frame, display: false)
        mirror.orderFrontRegardless()
        awaitingFirstFrame = true
        let scale = mirror.backingScaleFactor
        enqueue { [capture] in
            do {
                try await capture.start(pointSize: frame.size, scale: scale)
            } catch {
                Log.capture.error("start: \(error.localizedDescription)")
            }
        }
        Log.mirror.info("shown at \(frame.debugDescription)")
    }

    func hide() {
        guard shown else { return }
        shown = false
        awaitingFirstFrame = false
        restartAttempts = 0
        mirror.setVisible(false)
        mirror.clear()
        enqueue { [capture] in await capture.stop() }
        Log.mirror.info("hidden")
    }

    /// The system stopped the stream while the mirror is shown. Restart with backoff; give
    /// up and unpin after repeated failures so a dead mirror never sits over the window.
    private func restartAfterStop() {
        guard shown else { return }
        restartAttempts += 1
        guard restartAttempts <= Self.maxRestartAttempts else {
            Log.capture.error("stream failed \(self.restartAttempts - 1) times, unpinning")
            unpin()
            onGone?()
            return
        }
        let delay = Double(restartAttempts) * 0.5
        Log.capture.info("restarting stream in \(delay)s (attempt \(self.restartAttempts))")
        let size = mirror.frame.size
        let scale = mirror.backingScaleFactor
        enqueue { [weak self, capture] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.shown else { return }
            do {
                try await capture.start(pointSize: size, scale: scale)
            } catch {
                Log.capture.error("restart: \(error.localizedDescription)")
            }
        }
    }

    // The mirror moved to a display with a different scale factor: the stream must deliver
    // frames at the new pixel size or they come out blurry.
    func windowDidChangeBackingProperties(_ notification: Notification) {
        guard shown else { return }
        let size = mirror.frame.size
        let scale = mirror.backingScaleFactor
        enqueue { [capture] in await capture.resize(pointSize: size, scale: scale) }
    }

    func unpin() {
        hide()
        mirror.orderOut(nil)
        target.invalidate()
    }

    private func frameChanged(_ cgFrame: CGRect) {
        guard shown else { return }
        let frame = Geometry.appKitRect(fromCG: cgFrame)
        let resized = frame.size != mirror.frame.size
        mirror.setFrame(frame, display: true)
        if resized {
            let scale = mirror.backingScaleFactor
            enqueue { [capture] in await capture.resize(pointSize: frame.size, scale: scale) }
        }
    }

    /// A click on the mirror: activate the real window, drop the mirror, then replay the
    /// click at the same screen point so it lands in the real window.
    private func clicked(at point: CGPoint) {
        let cgPoint = Geometry.cgPoint(fromAppKit: point)
        Log.mirror.info("click at \(cgPoint.debugDescription), forwarding")
        hide()
        target.raise()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Self.postClick(at: cgPoint)
        }
    }

    private static func postClick(at point: CGPoint) {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = captureTask
        captureTask = Task { @MainActor in
            await previous?.value
            await work()
        }
    }
}
