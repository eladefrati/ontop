import AppKit

/// One Accessibility window, reduced to what matching reads.
struct AXWindowShape: Equatable {
    var frame: CGRect
    var title: String?
    var subrole: String?
}

/// The one rule for "this Accessibility window is that window-server window", used by the
/// menu, the hotkey and the pin. Accessibility has no lookup by window id, so: standard
/// windows only, frame within `tolerance` points on every edge, title breaking ties, first
/// wins. Standard windows only keeps out the helper window (subrole AXDialog, titled
/// "Window") that macOS adds to an app while one of its windows is being captured.
enum WindowMatch {
    static let tolerance: CGFloat = 2

    static func index(frame: CGRect, title: String?, in candidates: [AXWindowShape]) -> Int? {
        let matches = candidates.indices.filter { i in
            candidates[i].subrole == kAXStandardWindowSubrole && close(candidates[i].frame, frame)
        }
        if matches.count > 1, let title {
            return matches.first { candidates[$0].title == title } ?? matches.first
        }
        return matches.first
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance
            && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }
}

/// Typed readers over the untyped Accessibility attribute API.
enum AX {
    /// The system default is 6 s per call. An app that does not answer now costs the menu or
    /// the hotkey half a second: its first call, for the window list, times out.
    static let messagingTimeout: Float = 0.5

    /// The one way ontop makes an app's element, so every app element has the timeout.
    static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return app
    }

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

    /// An app's windows with what WindowMatch reads. Windows without a readable frame are skipped.
    static func windows(of app: AXUIElement) -> [(element: AXUIElement, shape: AXWindowShape)] {
        (elements(app, kAXWindowsAttribute) ?? []).compactMap { element in
            guard let frame = frame(of: element) else { return nil }
            let shape = AXWindowShape(frame: frame, title: string(of: element, kAXTitleAttribute),
                                      subrole: string(of: element, kAXSubroleAttribute))
            return (element, shape)
        }
    }
}
