import AppKit

/// One pinned window: places its mirror on the right desktops, shows the mirror while
/// another app is in front, hides it while the pinned window is frontmost, and hands clicks
/// on the mirror to the real window.
@MainActor
final class Pin: NSObject, NSWindowDelegate {
    enum EndReason {
        case user, windowGone, appQuit, captureFailed
    }

    let target: TargetWindow
    /// The window's title when it was pinned, for messages about this pin.
    let title: String
    private let capture: WindowCapture
    private let mirror = MirrorWindow()
    private var placement: MirrorPlacement = .notPlaced
    private var stream: MirrorStream = .hidden
    /// The gesture that began on the mirror, until it is delivered or dropped.
    private var forwarder: ClickForwarder?
    /// Serializes start, stop and resize so a stop never races a start in flight.
    private var captureTask: Task<Void, Never>?
    /// The pending start after a failure. Cancelled whenever the stream goes hidden.
    private var retryTask: Task<Void, Never>?
    private let context: () -> PinContext
    /// Tells the user about a problem that does not end the pin.
    private let report: (PinFailure) -> Void
    /// Asks the manager to end this pin. A pin never ends itself.
    private let onEnd: (EndReason) -> Void

    init(target: TargetWindow, title: String, capture: WindowCapture, context: @escaping () -> PinContext,
         report: @escaping (PinFailure) -> Void, onEnd: @escaping (EndReason) -> Void) {
        self.target = target
        self.title = title
        self.capture = capture
        self.context = context
        self.report = report
        self.onEnd = onEnd
        super.init()
        mirror.delegate = self
        capture.onFrame = { [weak self] surface in
            // A late frame after a hide leaves the stream hidden and is dropped.
            guard let self, self.send(.frame).showsFrames else { return }
            self.mirror.display(surface)
        }
        capture.onStopped = { [weak self] in self?.send(.stopped) }
        mirror.onMouse = { [weak self] event in self?.mouse(event) }
        target.onFrameChanged = { [weak self] frame in self?.frameChanged(frame) }
        target.onFocusChanged = { [weak self] in self?.evaluate() }
        target.onGone = { [weak self] in self?.onEnd(.windowGone) }
    }

    /// Places the mirror by MirrorPlacement, then shows or hides it by MirrorVisibility. The
    /// first call orders the mirror in. The manager calls it on every activation, desktop
    /// switch and Follow change; the pin itself on focus changes.
    func evaluate() {
        let context = context()
        let (next, order) = placement.next(followsDesktops: context.followsDesktops,
                                           windowOnScreen: { target.isOnScreen })
        mirror.setFollowsDesktops(context.followsDesktops)
        switch order {
        case .orderIn:
            // Joins the active desktop, which is the window's or, when following, every one.
            mirror.setFrame(Geometry.appKitRect(fromCG: target.frame), display: false)
            mirror.orderFrontRegardless()
        case .orderOut:
            send(.hide)
            mirror.orderOut(nil)
        case .none:
            break
        }
        placement = next
        let realWindowInFront = context.frontmostPID == target.pid && target.isFocusedInApp
        let onActiveDesktop = placement.isOnActiveDesktop(windowOnScreen: { target.isOnScreen },
                                                          mirrorOnActiveSpace: { mirror.isOnActiveSpace })
        let wanted = MirrorVisibility.wanted(realWindowInFront: realWindowInFront, onActiveDesktop: onActiveDesktop,
                                             recordingClick: forwarder?.isRecording ?? false)
        send(wanted ? .show : .hide)
    }

    /// The one place the stream state changes. Mirror alpha and click-through follow
    /// `showsFrames`.
    @discardableResult
    private func send(_ event: MirrorStream.Event) -> MirrorStream {
        let previous = stream
        let (next, effect) = previous.on(event)
        stream = next
        if next.showsFrames != previous.showsFrames { mirror.setVisible(next.showsFrames) }
        if next == .hidden, previous != .hidden {
            mirror.clear()
            retryTask?.cancel()
            retryTask = nil
        }
        switch effect {
        case .show:
            let frame = Geometry.appKitRect(fromCG: target.frame)
            mirror.setFrame(frame, display: false)
            mirror.orderFrontRegardless()
            startCapture()
            Log.mirror.info("shown at \(frame.debugDescription)")
        case .stop:
            enqueue { [capture] in await capture.stop() }
            Log.mirror.info("hidden")
        case .retry(let delay):
            Log.capture.info("capture failed, retrying in \(Int(delay / .milliseconds(1))) ms")
            scheduleRetry(after: delay)
        case .giveUp:
            Log.capture.error("capture failed \(MirrorStream.maxFailures + 1) times in a row, unpinning")
            onEnd(.captureFailed)
        case nil:
            break
        }
        return next
    }

    /// Starts the stream at the mirror's size and scale. A throw becomes `.startFailed`, so a
    /// failed start counts toward the limit like a stopped stream.
    private func startCapture() {
        let size = mirror.frame.size
        let scale = mirror.backingScaleFactor
        enqueue { [weak self, capture] in
            do {
                try await capture.start(pointSize: size, scale: scale)
            } catch {
                Log.capture.error("start: \(error.localizedDescription)")
                self?.send(.startFailed)
            }
        }
    }

    private func scheduleRetry(after delay: Duration) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.startCapture()
        }
    }

    // The mirror moved to a display with a different scale factor: the stream must deliver
    // frames at the new pixel size or they come out blurry.
    func windowDidChangeBackingProperties(_ notification: Notification) {
        guard stream != .hidden else { return }
        let size = mirror.frame.size
        let scale = mirror.backingScaleFactor
        enqueue { [capture] in await capture.resize(pointSize: size, scale: scale) }
    }

    /// Click dropped, stream stopped, mirror ordered out, observers removed. Idempotent. Called
    /// only by PinManager, the one place a pin ends.
    func end() {
        forwarder?.cancel()
        forwarder = nil
        send(.hide)
        mirror.orderOut(nil)
        placement = .notPlaced
        target.invalidate()
    }

    private func frameChanged(_ cgFrame: CGRect) {
        guard stream != .hidden else { return }
        let frame = Geometry.appKitRect(fromCG: cgFrame)
        let resized = frame.size != mirror.frame.size
        mirror.setFrame(frame, display: true)
        if resized {
            let scale = mirror.backingScaleFactor
            enqueue { [capture] in await capture.resize(pointSize: frame.size, scale: scale) }
        }
    }

    /// Every mouse button event on the mirror. The first down raises the real window; the
    /// gesture is recorded until every button is up, then delivered once the window's app is
    /// frontmost and the window is the top one at the point, which also means the mirror has
    /// cleared it.
    private func mouse(_ event: NSEvent) {
        guard let cgEvent = event.cgEvent else { return }
        if forwarder == nil {
            guard [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(cgEvent.type) else { return }
            forwarder = ClickForwarder(point: cgEvent.location)
            Log.mirror.info("click at \(cgEvent.location.debugDescription), forwarding")
            target.raise()
        }
        guard let forwarder, !forwarder.isComplete else { return }
        forwarder.record(cgEvent)
        guard forwarder.isComplete else { return }
        // The last button is up: the mirror may hide now and clear the point.
        evaluate()
        Task { [weak self] in
            guard let self else { return }
            let delivered = await forwarder.deliver(when: {
                context().frontmostPID == target.pid && WindowList.topWindow(at: forwarder.point) == target.windowID
            })
            guard self.forwarder === forwarder else { return }
            self.forwarder = nil
            if !delivered {
                Log.mirror.info("click dropped: the window did not come to the front")
                report(.clickNotDelivered(title: title))
            }
            evaluate()
        }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = captureTask
        captureTask = Task { @MainActor in
            await previous?.value
            await work()
        }
    }
}
