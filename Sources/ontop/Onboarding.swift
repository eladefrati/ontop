import AppKit

/// A permission ontop cannot work without.
enum Permission: Equatable {
    case accessibility
    case screenRecording

    var isGranted: Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .screenRecording: CGPreflightScreenCaptureAccess()
        }
    }
}

/// Walks the user through the two permissions. Accessibility takes effect at once;
/// Screen Recording takes effect only in a new process, so ontop relaunches itself.
@MainActor
enum Onboarding {
    private static let accessibilityPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    private static let screenRecordingPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

    enum Outcome {
        /// Every permission works in this process.
        case ready
        /// Screen Recording was granted after launch and works only in a new process. The
        /// caller builds nothing and calls `relaunch()`.
        case relaunch
    }

    enum Step: Equatable {
        case needs(Permission)
        case done(Outcome)
    }

    /// Accessibility first, then Screen Recording. A process that launched without Screen
    /// Recording never gets it, so once both are granted it relaunches instead of starting.
    static func step(accessibility: Bool, screenRecording: Bool, screenRecordingWasMissingAtLaunch: Bool) -> Step {
        if !accessibility { return .needs(.accessibility) }
        if !screenRecording { return .needs(.screenRecording) }
        return .done(screenRecordingWasMissingAtLaunch ? .relaunch : .ready)
    }

    /// Returns once both permissions are granted. Quits the app if the user declines.
    static func ensurePermissions() async -> Outcome {
        let screenRecordingWasMissingAtLaunch = !Permission.screenRecording.isGranted
        var asked: Permission?
        while true {
            switch step(accessibility: Permission.accessibility.isGranted,
                        screenRecording: Permission.screenRecording.isGranted,
                        screenRecordingWasMissingAtLaunch: screenRecordingWasMissingAtLaunch) {
            case .needs(let permission):
                if permission != asked {
                    asked = permission
                    ask(permission)
                }
                try? await Task.sleep(for: .seconds(1))
            case .done(let outcome):
                return outcome
            }
        }
    }

    private static func ask(_ permission: Permission) {
        switch permission {
        case .accessibility:
            _ = Permissions.ensureAccessibility()
            ask(title: "ontop needs Accessibility access",
                text: "It is used to bring a pinned window forward when you click its mirror and to follow the window when it moves or resizes.\n\nTurn on ontop under Accessibility, then come back; ontop continues on its own.",
                pane: accessibilityPane)
        case .screenRecording:
            _ = Permissions.ensureScreenRecording()
            ask(title: "ontop needs Screen Recording access",
                text: "It is used to list windows and to show a pinned window above other apps.\n\nTurn on ontop under Screen & System Audio Recording. ontop relaunches itself once it is on.",
                pane: screenRecordingPane)
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

    /// Opens a new instance of the bundle and terminates this one once it has started, or
    /// failed to start (logged; the user then opens ontop by hand).
    static func relaunch() {
        Log.app.info("screen recording granted, relaunching")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                Log.app.error("relaunch failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
