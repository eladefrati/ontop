import AppKit
import IOSurface

/// The floating window that shows the captured frames over the real window's position.
final class MirrorWindow: NSWindow {
    /// Called with the click location in AppKit screen coordinates.
    var onClick: ((CGPoint) -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .floating
        alphaValue = 0
        ignoresMouseEvents = true
        setFollowsDesktops(Settings.followsDesktops)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        let view = MirrorView()
        view.wantsLayer = true
        view.layer?.contentsGravity = .resize
        contentView = view
    }

    // The mirror never takes focus; focus belongs to the real window after a click.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// On every desktop and over full-screen apps, or on the desktop it was ordered in on.
    func setFollowsDesktops(_ follows: Bool) {
        collectionBehavior = follows ? [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle] : [.ignoresCycle]
    }

    /// The window stays ordered in so it keeps its desktop; visibility is alpha.
    func setVisible(_ visible: Bool) {
        alphaValue = visible ? 1 : 0
        ignoresMouseEvents = !visible
    }

    func display(_ surface: IOSurface) {
        contentView?.layer?.contents = surface
    }

    func clear() {
        contentView?.layer?.contents = nil
    }
}

private final class MirrorView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        (window as? MirrorWindow)?.onClick?(NSEvent.mouseLocation)
    }
}
