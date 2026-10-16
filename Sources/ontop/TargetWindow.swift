import AppKit
import ApplicationServices
import ScreenCaptureKit

/// The real window being pinned: its process, its Accessibility element, and observers that
/// report when it moves, resizes, minimizes or closes.
@MainActor
final class TargetWindow {
    let scWindow: SCWindow
    let pid: pid_t
    let app: NSRunningApplication
    private(set) var frame: CGRect
    private let appElement: AXUIElement
    private let element: AXUIElement
    private var observer: AXObserver?

    var onFrameChanged: ((CGRect) -> Void)?
    var onFocusChanged: (() -> Void)?
    var onGone: (() -> Void)?

    /// True when this window is the one its app would show in front: its focused window.
    var isFocusedInApp: Bool {
        guard let focused = AX.value(appElement, kAXFocusedWindowAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return false }
        return CFEqual(focused, element)
    }

    init?(scWindow: SCWindow) {
        guard let owner = scWindow.owningApplication,
              let app = NSRunningApplication(processIdentifier: owner.processID)
        else { return nil }
        self.scWindow = scWindow
        self.pid = owner.processID
        self.app = app
        self.frame = scWindow.frame
        self.appElement = AXUIElementCreateApplication(owner.processID)
        guard let element = Self.findElement(in: appElement, matching: scWindow) else {
            Log.target.error("no accessibility element matches window \(scWindow.windowID)")
            return nil
        }
        self.element = element
        installObserver()
    }

    /// Stops observing. Must be called by the owner before the target is released.
    func invalidate() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = nil
    }

    /// Brings the window to the front of its app and the app to the front of the screen.
    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        NSApp.yieldActivation(to: app)
        app.activate()
    }

    // MARK: Accessibility plumbing

    /// The Accessibility API has no public lookup by window ID, so the window is matched by
    /// frame and title among the app's windows.
    private static func findElement(in appElement: AXUIElement, matching window: SCWindow) -> AXUIElement? {
        guard let windows: [AXUIElement] = AX.elements(appElement, kAXWindowsAttribute) else { return nil }
        let candidates = windows.filter { element in
            guard let frame = AX.frame(of: element) else { return false }
            return abs(frame.origin.x - window.frame.origin.x) < 2
                && abs(frame.origin.y - window.frame.origin.y) < 2
                && abs(frame.width - window.frame.width) < 2
                && abs(frame.height - window.frame.height) < 2
        }
        if candidates.count > 1, let title = window.title {
            return candidates.first { AX.string(of: $0, kAXTitleAttribute) == title } ?? candidates.first
        }
        return candidates.first
    }

    private func installObserver() {
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let target = Unmanaged<TargetWindow>.fromOpaque(refcon).takeUnretainedValue()
            // The observer's run loop source is scheduled on the main run loop.
            MainActor.assumeIsolated { target.handle(notification as String) }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else {
            Log.target.error("AXObserverCreate failed for pid \(self.pid)")
            return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXMovedNotification, kAXResizedNotification,
                     kAXWindowMiniaturizedNotification, kAXUIElementDestroyedNotification] {
            let result = AXObserverAddNotification(observer, element, name as CFString, refcon)
            if result != .success {
                Log.target.error("AXObserverAddNotification \(name, privacy: .public) failed: \(result.rawValue)")
            }
        }
        // Focus changes are reported on the app, not the window.
        let focusResult = AXObserverAddNotification(observer, appElement, kAXFocusedWindowChangedNotification as CFString, refcon)
        if focusResult != .success {
            Log.target.error("AXObserverAddNotification focus failed: \(focusResult.rawValue)")
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = observer
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
            Log.target.info("target gone: \(notification, privacy: .public)")
            onGone?()
        default:
            break
        }
    }
}

/// Typed readers over the untyped Accessibility attribute API.
enum AX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == CFArrayGetTypeID() else { return nil }
        let array = raw as! CFArray as [AnyObject]
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    static func string(of element: AXUIElement, _ attribute: String) -> String? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == CFStringGetTypeID() else { return nil }
        return raw as! CFString as String
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let posRaw = value(element, kAXPositionAttribute), CFGetTypeID(posRaw) == AXValueGetTypeID(),
              let sizeRaw = value(element, kAXSizeAttribute), CFGetTypeID(sizeRaw) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRaw as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRaw as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
