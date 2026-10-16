import AppKit
import CoreGraphics

/// One pinned window: shows the mirror while another app is in front, hides it while the
/// pinned window is frontmost, and hands clicks on the mirror to the real window.
@MainActor
final class Pin {
    let target: TargetWindow
    private let capture: WindowCapture
    private let mirror = MirrorWindow()
    private var shown = false
    /// Serializes start, stop and resize so a stop never races a start in flight.
    private var captureTask: Task<Void, Never>?

    var onGone: (() -> Void)?

    init(target: TargetWindow) {
        self.target = target
        self.capture = WindowCapture(window: target.scWindow)
        capture.onFrame = { [mirror] surface in mirror.display(surface) }
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
    /// that app's focused window. Shown otherwise.
    func evaluate(frontmostPID: pid_t?) {
        if frontmostPID == target.pid && target.isFocusedInApp {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard !shown else { return }
        shown = true
        let frame = Geometry.appKitRect(fromCG: target.frame)
        mirror.clear()
        mirror.setFrame(frame, display: false)
        mirror.orderFrontRegardless()
        let scale = mirror.backingScaleFactor
        enqueue { [capture] in
            do {
                try await capture.start(pointSize: frame.size, scale: scale)
            } catch {
                Log.capture.error("start: \(error.localizedDescription, privacy: .public)")
            }
        }
        Log.mirror.info("shown at \(frame.debugDescription, privacy: .public)")
    }

    func hide() {
        guard shown else { return }
        shown = false
        mirror.orderOut(nil)
        enqueue { [capture] in await capture.stop() }
        Log.mirror.info("hidden")
    }

    func unpin() {
        hide()
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
        Log.mirror.info("click at \(cgPoint.debugDescription, privacy: .public), forwarding")
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
