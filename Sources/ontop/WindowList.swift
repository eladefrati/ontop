import AppKit

/// A window the user can pin, as the menu lists it.
struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let frame: CGRect
    /// False when its app marks the window as not capturable (sharing state none).
    let isCapturable: Bool
}

enum WindowList {
    /// On-screen, normal-level, titled, capturable windows of other apps, front to back,
    /// limited to windows that WindowMatch finds among their app's Accessibility windows.
    /// Those are the only ones ontop can pin.
    @MainActor
    static func onScreen() -> [WindowInfo] {
        accessible(candidates().filter(\.isCapturable))
    }

    /// The front window of the given app, if it has one on screen, capturable or not: the
    /// caller reports a window that can't be captured rather than pinning the app's next one.
    /// Filters by pid before any Accessibility call, so it reads that one app only.
    @MainActor
    static func frontWindow(ofPID pid: pid_t) -> WindowInfo? {
        accessible(candidates().filter { $0.pid == pid }).first
    }

    /// The process owning the window a click at a CG global point lands on: the top on-screen
    /// window there with alpha above 0. A hidden mirror is skipped; a shown one is the answer.
    static func topWindowOwner(at point: CGPoint) -> pid_t? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        return topWindowOwner(at: point, in: CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? [])
    }

    /// The owner of the first window, front to back and of any layer, with alpha above 0 whose
    /// bounds contain `point`.
    static func topWindowOwner(at point: CGPoint, in raw: [[String: Any]]) -> pid_t? {
        raw.first { info in
            guard (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds)
            else { return false }
            return rect.contains(point)
        }?[kCGWindowOwnerPID as String] as? pid_t
    }

    private static func candidates() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return parse(raw, ownPID: ProcessInfo.processInfo.processIdentifier)
    }

    /// Normal-level (layer 0) windows of other apps with alpha above 0, a title and bounds,
    /// front to back, from the window server's dictionaries.
    static func parse(_ raw: [[String: Any]], ownPID: pid_t) -> [WindowInfo] {
        raw.compactMap { info -> WindowInfo? in
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
            let sharing = info[kCGWindowSharingState as String] as? UInt32
            return WindowInfo(id: id, pid: pid, appName: appName, title: title, frame: CGRect(x: x, y: y, width: w, height: h),
                              isCapturable: sharing != CGWindowSharingType.none.rawValue)
        }
    }

    /// Keeps the windows WindowMatch finds among their app's Accessibility windows. Reads each
    /// app's windows once.
    @MainActor
    private static func accessible(_ windows: [WindowInfo]) -> [WindowInfo] {
        var axWindows: [pid_t: [AXWindowShape]] = [:]
        return windows.filter { window in
            if axWindows[window.pid] == nil {
                axWindows[window.pid] = AX.windows(of: AXUIElementCreateApplication(window.pid)).map(\.shape)
            }
            return WindowMatch.index(frame: window.frame, title: window.title, in: axWindows[window.pid]!) != nil
        }
    }
}
