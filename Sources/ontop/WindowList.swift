import AppKit

/// A window the user can pin, as the menu lists it.
struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let frame: CGRect
}

enum WindowList {
    /// On-screen, normal-level, titled windows of other apps, front to back, limited to
    /// windows the app exposes through Accessibility as standard windows. Those are the
    /// only ones ontop can pin. The filter also drops the small helper window (subrole
    /// AXDialog, titled "Window") that macOS adds to an app while one of its windows is
    /// being captured.
    @MainActor
    static func onScreen() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var accessibleFrames: [pid_t: [CGRect]] = [:]
        func isAccessible(_ window: WindowInfo) -> Bool {
            if accessibleFrames[window.pid] == nil {
                let app = AXUIElementCreateApplication(window.pid)
                accessibleFrames[window.pid] = (AX.elements(app, kAXWindowsAttribute) ?? [])
                    .filter { AX.string(of: $0, kAXSubroleAttribute) == kAXStandardWindowSubrole }
                    .compactMap(AX.frame(of:))
            }
            return accessibleFrames[window.pid]!.contains { frame in
                abs(frame.origin.x - window.frame.origin.x) < 2 && abs(frame.origin.y - window.frame.origin.y) < 2
                    && abs(frame.width - window.frame.width) < 2 && abs(frame.height - window.frame.height) < 2
            }
        }
        return raw.compactMap { info -> WindowInfo? in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPID,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let title = info[kCGWindowName as String] as? String, !title.isEmpty,
                  let appName = info[kCGWindowOwnerName as String] as? String,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"]
            else { return nil }
            return WindowInfo(id: id, pid: pid, appName: appName, title: title, frame: CGRect(x: x, y: y, width: w, height: h))
        }
        .filter(isAccessible)
    }

    /// The front window of the given app, if it has one on screen.
    @MainActor
    static func frontWindow(ofPID pid: pid_t) -> WindowInfo? {
        onScreen().first { $0.pid == pid }
    }
}
