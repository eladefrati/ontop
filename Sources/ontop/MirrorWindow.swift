import AppKit
import IOSurface

/// The floating window that shows the captured frames over the real window's position.
final class MirrorWindow: NSWindow {
    /// Called with the click location in AppKit screen coordinates.
    var onClick: ((CGPoint) -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        sharingType = .none
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
