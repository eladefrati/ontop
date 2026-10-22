// The pure decisions behind a Pin. Pin.swift executes them; the tests drive them directly.

/// A pin's capture stream. The mirror's alpha is derived from it (`showsFrames`).
enum MirrorStream: Equatable {
    /// No stream. Mirror transparent and click-through.
    case hidden
    /// Stream requested, no frame yet since showing. Mirror still transparent. `failures`
    /// counts failed starts since the last frame.
    case starting(failures: Int)
    /// Frames arriving. Mirror opaque.
    case live
    /// The stream died after frames had arrived. The last frame stays up while it restarts.
    case restarting(failures: Int)

    enum Event: Equatable {
        case show, hide, frame, startFailed, stopped
    }

    enum Effect: Equatable {
        /// Order the mirror front at the window's frame and start the stream.
        case show
        case stop
        /// Start the stream again after this delay.
        case retry(after: Duration)
        /// Too many failures in a row: the pin must end.
        case giveUp
    }

    /// Failures in a row that are retried; the next one gives up.
    static let maxFailures = 3

    var showsFrames: Bool {
        switch self {
        case .live, .restarting: true
        case .hidden, .starting: false
        }
    }

    /// Late callbacks (a frame, a failure or a stop after a hide) are ignored while hidden.
    /// A failed start counts toward `maxFailures` exactly like a stopped stream; a frame
    /// resets the count by moving to `.live`.
    func on(_ event: Event) -> (next: MirrorStream, effect: Effect?) {
        switch (self, event) {
        case (.hidden, .show): (.starting(failures: 0), .show)
        case (.hidden, _): (.hidden, nil)
        case (_, .hide): (.hidden, .stop)
        case (_, .frame): (.live, nil)
        case (_, .show): (self, nil)
        case (.starting(let failures), .startFailed), (.starting(let failures), .stopped):
            Self.fail(after: failures, as: MirrorStream.starting)
        case (.live, .startFailed), (.live, .stopped):
            Self.fail(after: 0, as: MirrorStream.restarting)
        case (.restarting(let failures), .startFailed), (.restarting(let failures), .stopped):
            Self.fail(after: failures, as: MirrorStream.restarting)
        }
    }

    private static func fail(after failures: Int, as state: (Int) -> MirrorStream) -> (next: MirrorStream, effect: Effect?) {
        let count = failures + 1
        guard count <= maxFailures else { return (.hidden, .giveUp) }
        return (state(count), .retry(after: .milliseconds(500 * count)))
    }
}

enum MirrorVisibility {
    /// Hidden while the real window is what the user sees: its app is frontmost and it is
    /// that app's focused window. Also hidden while the mirror's desktop is not the active
    /// one, since nobody could see it and the stream would run for nothing. Shown otherwise.
    static func wanted(realWindowInFront: Bool, onActiveDesktop: Bool) -> Bool {
        !realWindowInFront && onActiveDesktop
    }
}

/// Where the mirror window lives (ADR-0003). macOS has no public call to put a window on a
/// chosen desktop: a window joins the desktop that is active when it is ordered in, and keeps
/// the active one when it stops joining all desktops. So a mirror that must live on its
/// window's desktop is ordered in only while that desktop is active, which is exactly while
/// the window is on screen.
enum MirrorPlacement: Equatable {
    /// Ordered out: Follow is off and the window's desktop has not been active since.
    case notPlaced
    /// Ordered in on the window's desktop only.
    case windowDesktop
    /// Ordered in on every desktop and over full-screen apps.
    case everyDesktop

    enum Order: Equatable {
        case none, orderIn, orderOut
    }

    /// `windowOnScreen` is read only when the answer depends on it.
    func next(followsDesktops: Bool, windowOnScreen: () -> Bool) -> (next: MirrorPlacement, order: Order) {
        switch (self, followsDesktops) {
        case (.notPlaced, true):
            return (.everyDesktop, .orderIn)
        case (_, true):
            return (.everyDesktop, .none)
        case (.windowDesktop, false):
            return (.windowDesktop, .none)
        case (.everyDesktop, false):
            // On screen, the active desktop is the window's, and the mirror stays on it.
            return windowOnScreen() ? (.windowDesktop, .none) : (.notPlaced, .orderOut)
        case (.notPlaced, false):
            return windowOnScreen() ? (.windowDesktop, .orderIn) : (.notPlaced, .none)
        }
    }

    /// Whether the mirror is on the active desktop. NSWindow.isOnActiveSpace alone is wrong
    /// around ordering: it reads false for a moment after the mirror is ordered in (seen
    /// still false right after orderFrontRegardless and on the next evaluate, true 200 ms
    /// later), and an ordered-out mirror can read true. A mirror on its window's desktop is
    /// on the active one while the window is on screen; otherwise, as for a hidden app's
    /// window, the mirror's own report decides.
    func isOnActiveDesktop(windowOnScreen: () -> Bool, mirrorOnActiveSpace: () -> Bool) -> Bool {
        switch self {
        case .notPlaced: false
        case .everyDesktop: true
        case .windowDesktop: windowOnScreen() || mirrorOnActiveSpace()
        }
    }
}
