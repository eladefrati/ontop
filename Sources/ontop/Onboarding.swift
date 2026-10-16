import AppKit

/// Walks the user through the two permissions. Accessibility takes effect at once;
/// Screen Recording takes effect only in a new process, so ontop relaunches itself.
@MainActor
enum Onboarding {
    private static let accessibilityPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    private static let screenRecordingPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

    /// Returns when both permissions are granted. Quits the app if the user declines.
    static func ensurePermissions() async {
        if !Permissions.ensureAccessibility() {
            ask(title: "ontop needs Accessibility access",
                text: "It is used to bring a pinned window forward when you click its mirror and to follow the window when it moves or resizes.\n\nTurn on ontop under Accessibility, then come back; ontop continues on its own.",
                pane: accessibilityPane)
            while !AXIsProcessTrusted() {
                try? await Task.sleep(for: .seconds(1))
            }
            Log.app.info("accessibility granted")
        }
        if !Permissions.ensureScreenRecording() {
            ask(title: "ontop needs Screen Recording access",
                text: "It is used to list windows and to show a pinned window above other apps.\n\nTurn on ontop under Screen & System Audio Recording. ontop relaunches itself once it is on.",
                pane: screenRecordingPane)
            while !CGPreflightScreenCaptureAccess() {
                try? await Task.sleep(for: .seconds(1))
            }
            Log.app.info("screen recording granted, relaunching")
            relaunch()
        }
    }

    private static func ask(title: String, text: String, pane: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: pane) {
            NSWorkspace.shared.open(url)
        } else {
            NSApp.terminate(nil)
        }
    }

    private static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                Log.app.error("relaunch failed: \(error.localizedDescription, privacy: .public)")
            }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
