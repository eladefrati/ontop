import AppKit

enum Permissions {
    /// True when Screen Recording is granted. Otherwise asks the system to show its prompt
    /// once; the grant takes effect on the next launch.
    static func ensureScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    /// True when Accessibility is granted. Otherwise shows the system prompt that opens
    /// the Privacy & Security pane; the grant takes effect immediately.
    static func ensureAccessibility() -> Bool {
        // The key is a C global the compiler cannot prove immutable; it is a constant string.
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}
