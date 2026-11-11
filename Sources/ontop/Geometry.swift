import AppKit

/// CoreGraphics, ScreenCaptureKit and the Accessibility API use a top-left origin on the
/// primary display. AppKit uses a bottom-left origin on the same display. These helpers
/// convert between the two.
enum Geometry {
    /// Height of the primary display, the one that carries the menu bar and the origin.
    /// Both coordinate systems are global across displays and differ only in which corner
    /// of this one display is the origin, so this single flip is right for every display.
    @MainActor
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// The size in points of what a captured frame shows, the window with its child windows,
    /// from the frame's content rect in the surface and the scale it was drawn at. Measured on
    /// a 640 x 420 window with an 880 pt wide sheet, in a 640 x 420 stream: a content rect of
    /// 640 x 375.27 at scale 0.727, which is 880 x 516.
    static func contentSize(rect: CGRect, scale: CGFloat) -> CGSize {
        guard scale > 0 else { return rect.size }
        return CGSize(width: (rect.width / scale).rounded(), height: (rect.height / scale).rounded())
    }

    @MainActor
    static func appKitRect(fromCG rect: CGRect, primaryHeight: CGFloat = Geometry.primaryHeight) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
