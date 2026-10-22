import AppKit

/// The real window being pinned: its process, its Accessibility element, and observers that
/// report when it moves, resizes, minimizes or closes.
@MainActor
final class TargetWindow {
    let windowID: CGWindowID
    let pid: pid_t
    let app: NSRunningApplication
    private(set) var frame: CGRect
    private let appElement: AXUIElement
    private let element: AXUIElement
    private var observer: AXObserver?
    /// The observer's refcon holds a retain on self, released in `invalidate()`, so a
    /// callback can never reach a freed target.
    private var refcon: Unmanaged<TargetWindow>?

    var onFrameChanged: ((CGRect) -> Void)?
    var onFocusChanged: (() -> Void)?
    var onGone: (() -> Void)?

    /// True when this window is the one its app would show in front: its focused window, or
    /// the window of a focused sheet, which its app reports as the focused window instead.
    var isFocusedInApp: Bool {
        guard let focused = AX.value(appElement, kAXFocusedWindowAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return false }
        if CFEqual(focused, element) { return true }
        return AX.value(focused as! AXUIElement, kAXParentAttribute).map { CFEqual($0, element) } ?? false
    }

    /// Finds the window among its app's standard Accessibility windows by WindowMatch, the
    /// rule the menu lists windows by.
    init?(windowID: CGWindowID, pid: pid_t, frame: CGRect, title: String?) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        self.windowID = windowID
        self.pid = pid
        self.app = app
        self.frame = frame
        self.appElement = AXUIElementCreateApplication(pid)
        let windows = AX.windows(of: appElement)
        guard let index = WindowMatch.index(frame: frame, title: title, in: windows.map(\.shape)) else {
            Log.target.error("no accessibility element matches window \(windowID)")
            return nil
        }
        self.element = windows[index].element
        // Without an observer the pin would never follow the window's moves or end on close.
        guard installObserver() else { return nil }
    }

    /// True while the window is on screen. For a window on a desktop that means its desktop
    /// is the active one.
    var isOnScreen: Bool {
        let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]]
        return info?.first?[kCGWindowIsOnscreen as String] as? Bool ?? false
    }

    /// Stops observing and releases the refcon's retain. Idempotent. Until it is called the
    /// target keeps itself alive.
    func invalidate() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            self.observer = nil
        }
        refcon?.release()
        refcon = nil
    }

    /// Brings the window to the front of its app and the app to the front of the screen.
    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        NSApp.yieldActivation(to: app)
        app.activate()
    }

    // MARK: Accessibility plumbing

    /// False when no observer could be created.
    private func installObserver() -> Bool {
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let target = Unmanaged<TargetWindow>.fromOpaque(refcon).takeUnretainedValue()
            // The observer's run loop source is scheduled on the main run loop.
            MainActor.assumeIsolated { target.handle(notification as String) }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else {
            Log.target.error("AXObserverCreate failed for pid \(self.pid)")
            return false
        }
        let retained = Unmanaged.passRetained(self)
        self.refcon = retained
        let refcon = retained.toOpaque()
        for name in [kAXMovedNotification, kAXResizedNotification,
                     kAXWindowMiniaturizedNotification, kAXUIElementDestroyedNotification] {
            let result = AXObserverAddNotification(observer, element, name as CFString, refcon)
            if result != .success {
                Log.target.error("AXObserverAddNotification \(name) failed: \(result.rawValue)")
            }
        }
        // Focus changes are reported on the app, not the window.
        let focusResult = AXObserverAddNotification(observer, appElement, kAXFocusedWindowChangedNotification as CFString, refcon)
        if focusResult != .success {
            Log.target.error("AXObserverAddNotification focus failed: \(focusResult.rawValue)")
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = observer
        return true
    }

    private func handle(_ notification: String) {
        switch notification {
        case kAXMovedNotification, kAXResizedNotification:
            guard let frame = AX.frame(of: element) else { return }
            self.frame = frame
            onFrameChanged?(frame)
        case kAXFocusedWindowChangedNotification:
            onFocusChanged?()
        case kAXWindowMiniaturizedNotification, kAXUIElementDestroyedNotification:
            Log.target.info("target gone: \(notification)")
            onGone?()
        default:
            break
        }
    }
}
