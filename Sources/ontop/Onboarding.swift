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

    /// Asks macOS for the permission. Its prompt is the one dialog per permission and is
    /// what lists ontop in Privacy & Security. macOS decides whether the prompt appears.
    func request() {
        switch self {
        case .accessibility:
            // The key is a C global the compiler cannot prove immutable; it is a constant string.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
    }

    /// The permission's pane in Privacy & Security.
    var settingsURL: URL {
        switch self {
        case .accessibility: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .screenRecording: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        }
    }

    var title: String {
        switch self {
        case .accessibility: "ontop needs Accessibility access"
        case .screenRecording: "ontop needs Screen Recording access"
        }
    }

    var reason: String {
        switch self {
        case .accessibility: "To bring a pinned window forward when you click its mirror and follow it when it moves."
        case .screenRecording: "To list windows and show a pinned window above other apps. ontop relaunches once it is on."
        }
    }
}

/// Walks the user through the two permissions. Accessibility takes effect at once;
/// Screen Recording takes effect only in a new process, so ontop relaunches itself.
@MainActor
enum Onboarding {
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

    /// Returns at once when both permissions are granted. Otherwise, for each missing one in
    /// turn, reports it through `onWaiting`, asks macOS for it once, and checks every second
    /// until it is granted. ontop shows no dialog of its own: the status menu explains what
    /// is missing and offers Quit throughout.
    static func run(onWaiting: (Permission) -> Void) async -> Outcome {
        let screenRecordingWasMissingAtLaunch = !Permission.screenRecording.isGranted
        var asked: Permission?
        while true {
            switch step(accessibility: Permission.accessibility.isGranted,
                        screenRecording: Permission.screenRecording.isGranted,
                        screenRecordingWasMissingAtLaunch: screenRecordingWasMissingAtLaunch) {
            case .needs(let permission):
                if permission != asked {
                    asked = permission
                    onWaiting(permission)
                    permission.request()
                }
                try? await Task.sleep(for: .seconds(1))
            case .done(let outcome):
                return outcome
            }
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
