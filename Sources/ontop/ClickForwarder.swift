import AppKit

/// Carries a mouse gesture that landed on a mirror to the real window. Records it, any button
/// with its drags, modifiers and click count, from the first button down until every button is
/// up, then posts it once the caller says the real window is in front at that point. A window
/// that does not come forward within the deadline loses the gesture rather than it landing on
/// whatever is underneath.
///
/// Nothing is posted while a hardware button is held, so a drag on a mirror takes effect when
/// the button is released. A forwarder carries one gesture: events after its last button up are
/// ignored, so a click on the mirror while one is being delivered is dropped.
@MainActor
final class ClickForwarder {
    /// CG global location of the first button down.
    let point: CGPoint
    private var recording: [CGEvent] = []
    private var buttonsDown = 0
    private var cancelled = false
    /// Posts one event. Tests pass a collector, so a test run never clicks on the screen.
    private let post: @MainActor (CGEvent) -> Void

    init(point: CGPoint, post: @escaping @MainActor (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }) {
        self.point = point
        self.post = post
    }

    /// A button of the gesture is still down.
    var isRecording: Bool { buttonsDown > 0 }

    /// Every button of the gesture is up again.
    var isComplete: Bool { !recording.isEmpty && buttonsDown == 0 }

    /// Keeps the event's button, location, modifier flags and click state, so a double-click
    /// replays as one. A drag or up before any down is ignored.
    func record(_ event: CGEvent) {
        guard !isComplete else { return }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            buttonsDown += 1
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            guard buttonsDown > 0 else { return }
            buttonsDown -= 1
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            guard buttonsDown > 0 else { return }
        default:
            return
        }
        if let replay = Self.replay(of: event) { recording.append(replay) }
    }

    /// A new event, not a copy: a copy keeps what the window server recorded when it routed the
    /// original to the mirror, and posted again it lands on the mirror.
    private static func replay(of event: CGEvent) -> CGEvent? {
        let button = CGMouseButton(rawValue: UInt32(event.getIntegerValueField(.mouseEventButtonNumber))) ?? .left
        guard let replay = CGEvent(mouseEventSource: nil, mouseType: event.type, mouseCursorPosition: event.location,
                                   mouseButton: button)
        else { return nil }
        replay.flags = event.flags
        replay.setIntegerValueField(.mouseEventClickState, value: event.getIntegerValueField(.mouseEventClickState))
        return replay
    }

    /// Checks once per frame until `isReady()` holds, then posts the gesture in order and
    /// returns true. Returns false, posting nothing, at the deadline or after `cancel()`.
    func deliver(deadline: Duration = .seconds(1), when isReady: @MainActor () -> Bool) async -> Bool {
        let end = ContinuousClock.now + deadline
        while !cancelled {
            if isReady() {
                for event in recording { post(event) }
                return true
            }
            guard ContinuousClock.now < end else { return false }
            try? await Task.sleep(for: .milliseconds(16))
        }
        return false
    }

    func cancel() {
        cancelled = true
    }
}
