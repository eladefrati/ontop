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

    /// Asks macOS for the permission. Its prompt is the one dialog per permission; macOS
    /// decides whether it appears. For Screen Recording on macOS 26 the request does not
    /// add ontop to the Privacy & Security list, so the user may have to add it with +.
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
        case .screenRecording: "To list windows and show a pinned window above other apps. Add ontop with + if it isn't listed, turn it on, then choose Quit & Reopen."
        }
    }
}

/// Walks the user through the two permissions. Accessibility takes effect at once.
/// ontop does not detect a Screen Recording grant in a running process and relies on a
/// relaunch: macOS's Quit & Reopen, the menu's Relaunch ontop, or Quit and open.
@MainActor
enum Onboarding {
    enum Step: Equatable {
        case needs(Permission)
        case ready
    }

    /// Accessibility first, then Screen Recording.
    static func step(accessibility: Bool, screenRecording: Bool) -> Step {
        if !accessibility { return .needs(.accessibility) }
        if !screenRecording { return .needs(.screenRecording) }
        return .ready
    }

    /// Returns at once when both permissions are granted. Otherwise, for each missing one in
    /// turn, reports it through `onWaiting` and asks macOS for it once. Accessibility is then
    /// checked every second until it is granted. Screen Recording is not checked again:
    /// `CGPreflightScreenCaptureAccess` keeps its launch value for the life of the process,
    /// and asking ScreenCaptureKit instead makes macOS prompt on every check, so `run` never
    /// returns and the process waits for the user to relaunch it. ontop shows no dialog of
    /// its own: the status menu explains what is missing and offers Quit throughout.
    static func run(onWaiting: (Permission) -> Void) async {
        var askedForAccessibility = false
        while true {
            switch step(accessibility: Permission.accessibility.isGranted,
                        screenRecording: Permission.screenRecording.isGranted) {
            case .needs(.accessibility):
                if !askedForAccessibility {
                    askedForAccessibility = true
                    onWaiting(.accessibility)
                    Permission.accessibility.request()
                }
                try? await Task.sleep(for: .seconds(1))
            case .needs(.screenRecording):
                onWaiting(.screenRecording)
                Permission.screenRecording.request()
                // Never resumed: only a relaunch ends this wait.
                await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
            case .ready:
                return
            }
        }
    }

    /// Opens a new instance of the bundle and terminates this one once it has started. When it
    /// fails to start, logs why, keeps this one running and calls `onFailure`.
    static func relaunch(onFailure: @escaping @MainActor () -> Void) {
        Log.app.info("relaunching")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                Log.app.error("relaunch failed: \(error.localizedDescription)")
                DispatchQueue.main.async { onFailure() }
            } else {
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
    }
}
