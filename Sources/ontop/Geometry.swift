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

    @MainActor
    static func appKitRect(fromCG rect: CGRect, primaryHeight: CGFloat = Geometry.primaryHeight) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    @MainActor
    static func cgPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
