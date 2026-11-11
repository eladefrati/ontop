import AppKit
import IOSurface

/// The floating window that shows the captured frames over the real window's position.
///
/// `ignoresMouseEvents` is never set. Left alone, macOS gives the mirror a click only where it
/// shows a pixel, so a hidden mirror, and the empty corners of one that covers a sheet wider
/// than its window, pass the click to whatever is underneath. Setting it, even to false, makes
/// the whole rectangle take clicks (measured 2026-11-10).
final class MirrorWindow: NSWindow {
    /// Every mouse button event on the mirror: downs, drags and ups of any button.
    var onMouse: ((NSEvent) -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .floating
        alphaValue = 0
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        let view = NSView()
        view.wantsLayer = true
        view.layer?.contentsGravity = .resize
        contentView = view
    }

    // The mirror never takes focus; focus belongs to the real window after a click.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Mouse button events go to `onMouse` and never reach a view.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp,
             .rightMouseDown, .rightMouseDragged, .rightMouseUp,
             .otherMouseDown, .otherMouseDragged, .otherMouseUp:
            onMouse?(event)
        default:
            super.sendEvent(event)
        }
    }

    /// On every desktop and over full-screen apps, or on the desktop it was ordered in on.
    func setFollowsDesktops(_ follows: Bool) {
        let behavior: NSWindow.CollectionBehavior = follows ? [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle] : [.ignoresCycle]
        if collectionBehavior != behavior { collectionBehavior = behavior }
    }

    /// The window stays ordered in so it keeps its desktop; visibility is alpha.
    func setVisible(_ visible: Bool) {
        alphaValue = visible ? 1 : 0
    }

    func display(_ surface: IOSurface) {
        contentView?.layer?.contents = surface
    }

    func clear() {
        contentView?.layer?.contents = nil
    }
}
