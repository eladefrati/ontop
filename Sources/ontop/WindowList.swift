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
    /// windows that WindowMatch finds among their app's Accessibility windows. Those are the
    /// only ones ontop can pin.
    @MainActor
    static func onScreen() -> [WindowInfo] {
        accessible(candidates())
    }

    /// The front window of the given app, if it has one on screen. Filters by pid before
    /// any Accessibility call, so it reads that one app only.
    @MainActor
    static func frontWindow(ofPID pid: pid_t) -> WindowInfo? {
        accessible(candidates().filter { $0.pid == pid }).first
    }

    /// The window server's on-screen, normal-level, titled windows of other apps, front to back.
    private static func candidates() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
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
    }

    /// Keeps the windows WindowMatch finds among their app's Accessibility windows. Reads each
    /// app's windows once.
    @MainActor
    private static func accessible(_ windows: [WindowInfo]) -> [WindowInfo] {
        var axWindows: [pid_t: [AXWindowShape]] = [:]
        return windows.filter { window in
            if axWindows[window.pid] == nil {
                axWindows[window.pid] = AX.windows(of: AX.application(window.pid)).map(\.shape)
            }
            return WindowMatch.index(frame: window.frame, title: window.title, in: axWindows[window.pid]!) != nil
        }
    }
}
