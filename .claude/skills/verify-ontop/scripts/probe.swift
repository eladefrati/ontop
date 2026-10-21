// Verification probe for ontop: observes windows and desktops, and drives the app the way a
// user would (hotkey, menu, clicks) through CGEvent and Accessibility. Test tooling only; the
// private SkyLight calls below are for observing desktops and never go into the app (ADR-0001).
// Every command prints JSON on stdout. Run through ./probe, which compiles this file.

import AppKit
import ApplicationServices
import CoreGraphics

// MARK: Private window-server calls (desktop observation only)

@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSGetActiveSpace") func CGSGetActiveSpace(_ cid: Int32) -> UInt64
@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray
@_silgen_name("CGSCopySpacesForWindows") func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ windows: CFArray) -> CFArray

// MARK: Output

func emit(_ value: Any) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("probe: \(message)\n".data(using: .utf8)!)
    exit(1)
}

func sleepMs(_ ms: Int) { usleep(useconds_t(ms * 1000)) }

// MARK: Desktops

struct Desktop {
    let display: String
    let index: Int // 1-based, in Mission Control order; full-screen spaces count too
    let space: UInt64
    let type: Int // 0 desktop, 4 full-screen app
}

func desktops() -> (all: [Desktop], current: [String: UInt64]) {
    let cid = CGSMainConnectionID()
    var all: [Desktop] = []
    var current: [String: UInt64] = [:]
    for case let display as [String: Any] in CGSCopyManagedDisplaySpaces(cid) as NSArray {
        let name = display["Display Identifier"] as? String ?? "?"
        if let cur = display["Current Space"] as? [String: Any], let id = (cur["id64"] ?? cur["ManagedSpaceID"]) as? NSNumber {
            current[name] = id.uint64Value
        }
        for (i, space) in ((display["Spaces"] as? [[String: Any]]) ?? []).enumerated() {
            let id = ((space["id64"] ?? space["ManagedSpaceID"]) as? NSNumber)?.uint64Value ?? 0
            all.append(Desktop(display: name, index: i + 1, space: id, type: (space["type"] as? NSNumber)?.intValue ?? 0))
        }
    }
    return (all, current)
}

func desktopJSON(_ d: Desktop) -> [String: Any] {
    ["display": d.display, "desktop": d.index, "space": d.space, "fullscreen": d.type == 4]
}

func spacesOf(_ wid: CGWindowID) -> [UInt64] {
    let ids = CGSCopySpacesForWindows(CGSMainConnectionID(), 0x7, [NSNumber(value: wid)] as CFArray) as NSArray
    return ids.compactMap { ($0 as? NSNumber)?.uint64Value }
}

func activeSpace() -> UInt64 { CGSGetActiveSpace(CGSMainConnectionID()) }

// MARK: Windows

func windowList(all: Bool) -> [[String: Any]] {
    let options: CGWindowListOption = all ? [.optionAll, .excludeDesktopElements] : [.optionOnScreenOnly, .excludeDesktopElements]
    return (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
}

func windowJSON(_ info: [String: Any]) -> [String: Any] {
    let b = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    let wid = info[kCGWindowNumber as String] as? CGWindowID ?? 0
    let (all, _) = desktops()
    let spaces = spacesOf(wid)
    return [
        "id": wid,
        "pid": info[kCGWindowOwnerPID as String] as? Int ?? 0,
        "owner": info[kCGWindowOwnerName as String] as? String ?? "",
        "name": info[kCGWindowName as String] as? String ?? "",
        "layer": info[kCGWindowLayer as String] as? Int ?? 0,
        "alpha": info[kCGWindowAlpha as String] as? Double ?? 1,
        "onscreen": info[kCGWindowIsOnscreen as String] as? Bool ?? false,
        "bounds": [b["X"] ?? 0, b["Y"] ?? 0, b["Width"] ?? 0, b["Height"] ?? 0],
        "spaces": spaces,
        "desktops": spaces.compactMap { s in all.first { $0.space == s }.map(desktopJSON) },
    ]
}

// MARK: Accessibility

func axValue(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
}

func axChildren(_ el: AXUIElement, _ attr: String = kAXChildrenAttribute) -> [AXUIElement] {
    guard let raw = axValue(el, attr), CFGetTypeID(raw) == CFArrayGetTypeID() else { return [] }
    return (raw as! [AnyObject]).compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
}

func axString(_ el: AXUIElement, _ attr: String) -> String? { axValue(el, attr) as? String }

func axElement(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
    guard let raw = axValue(el, attr), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
    return (raw as! AXUIElement)
}

func axFrame(_ el: AXUIElement) -> CGRect? {
    guard let p = axValue(el, kAXPositionAttribute), let s = axValue(el, kAXSizeAttribute) else { return nil }
    var origin = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &origin)
    AXValueGetValue(s as! AXValue, .cgSize, &size)
    return CGRect(origin: origin, size: size)
}

func axWindow(pid: pid_t, title: String) -> AXUIElement {
    let app = AXUIElementCreateApplication(pid)
    guard let w = axChildren(app, kAXWindowsAttribute).first(where: { axString($0, kAXTitleAttribute) == title }) else {
        fail("no window titled \"\(title)\" in pid \(pid)")
    }
    return w
}

func findDescendant(_ el: AXUIElement, role: String, depth: Int = 0) -> AXUIElement? {
    if axString(el, kAXRoleAttribute) == role { return el }
    guard depth < 8 else { return nil }
    for child in axChildren(el) {
        if let hit = findDescendant(child, role: role, depth: depth + 1) { return hit }
    }
    return nil
}

func setFrontmost(_ pid: pid_t) {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
}

// MARK: Events

func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
    let source = CGEventSource(stateID: .hidSystemState)
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    else { fail("could not create key events") }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    sleepMs(20)
    up.post(tap: .cghidEventTap)
}

func postClick(_ point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
            fail("could not create mouse event")
        }
        if type != .mouseMoved { e.setIntegerValueField(.mouseEventClickState, value: 1) }
        e.post(tap: .cghidEventTap)
        sleepMs(30)
    }
}

// MARK: Menu (ontop's status item, through Accessibility)

func menuItems(_ menu: AXUIElement) -> [[String: Any]] {
    // The window list sits between the first and second separators; in it, a disabled item
    // with a title is an app header and the items under it are that app's windows.
    var section = ""
    var separators = 0
    return axChildren(menu).map { item in
        let title = axString(item, kAXTitleAttribute) ?? ""
        let enabled = (axValue(item, kAXEnabledAttribute) as? Bool) ?? false
        let mark = axString(item, kAXMenuItemMarkCharAttribute) ?? ""
        if title.isEmpty && !enabled {
            separators += 1
            section = ""
        } else if separators == 1 && !enabled && title != "No Windows" {
            section = title
        }
        return ["title": title, "enabled": enabled, "checked": !mark.isEmpty, "section": section]
    }
}

/// Opens the status item's menu and returns the open AXMenu. AXPress on a status item runs
/// the menu's tracking loop inside the press, so the press call itself times out; the menu
/// is open and answers Accessibility queries all the same.
func statusItem(pid: pid_t) -> AXUIElement {
    let app = AXUIElementCreateApplication(pid)
    guard let bar = axElement(app, "AXExtrasMenuBar"), let item = axChildren(bar).first else {
        fail("ontop (pid \(pid)) has no status item")
    }
    return item
}

/// The status item's menu while it is open. The AXMenu child outlives the menu with its old
/// items, so open is read from the item's AXSelected, which is true only while it is shown.
func openMenuOf(_ item: AXUIElement) -> AXUIElement? {
    guard (axValue(item, kAXSelectedAttribute) as? Bool) == true else { return nil }
    return axChildren(item).first { axString($0, kAXRoleAttribute) == kAXMenuRole && !axChildren($0).isEmpty }
}

/// Waits until the status item's menu is closed, so the next command opens a rebuilt menu.
func waitMenuClosed(pid: pid_t) {
    let item = statusItem(pid: pid)
    for _ in 0..<40 {
        if (axValue(item, kAXSelectedAttribute) as? Bool) != true { return }
        sleepMs(50)
    }
    fail("menu did not close")
}

func openMenu(pid: pid_t) -> AXUIElement {
    waitMenuClosed(pid: pid)
    let item = statusItem(pid: pid)
    AXUIElementSetMessagingTimeout(item, 0.3)
    AXUIElementPerformAction(item, kAXPressAction as CFString)
    for _ in 0..<40 {
        if let menu = openMenuOf(item) { return menu }
        sleepMs(50)
    }
    fail("menu did not open")
}

func closeMenu(_ menu: AXUIElement, pid: pid_t) {
    AXUIElementPerformAction(menu, kAXCancelAction as CFString)
    waitMenuClosed(pid: pid)
}

// MARK: Cover app

/// A throwaway regular app with one window, used as "another app in front". Runs until
/// killed. Prints its pid and window id once the window is up.
final class CoverDelegate: NSObject, NSApplicationDelegate {
    let rect: CGRect
    let title: String
    var window: NSWindow?
    init(rect: CGRect, title: String) { self.rect = rect; self.title = title }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let frame = NSRect(x: rect.minX, y: primary - rect.minY - rect.height, width: rect.width, height: rect.height)
        let w = NSWindow(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.35, blue: 0.2, alpha: 1)
        w.makeKeyAndOrderFront(nil)
        window = w
        NSApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            emit(["pid": ProcessInfo.processInfo.processIdentifier, "window": w.windowNumber, "title": self.title])
        }
    }
}

// MARK: Commands

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    fail("usage: probe <windows|front|activate|hotkey|space|desktops|menu|click|ax-windows|ax-place|ax-raise|ax-close|ax-caret|cover|trusted> ...")
}
args.removeFirst()

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func positional(_ i: Int, _ what: String) -> String {
    let plain = args.enumerated().filter { idx, a in !a.hasPrefix("--") && (idx == 0 || !args[idx - 1].hasPrefix("--")) }.map(\.element)
    guard i < plain.count else { fail("missing \(what)") }
    return plain[i]
}

func pidArg(_ i: Int) -> pid_t {
    guard let pid = pid_t(positional(i, "pid")) else { fail("pid must be a number") }
    return pid
}

switch command {
case "trusted":
    emit(["accessibility": AXIsProcessTrusted(), "screenRecording": CGPreflightScreenCaptureAccess()])

case "windows":
    // probe windows [--pid N] [--owner NAME] [--all]
    let pid = option("--pid").flatMap(Int.init)
    let owner = option("--owner")
    let rows = windowList(all: args.contains("--all")).filter { info in
        (pid == nil || info[kCGWindowOwnerPID as String] as? Int == pid)
            && (owner == nil || info[kCGWindowOwnerName as String] as? String == owner)
    }
    emit(rows.map(windowJSON))

case "front":
    let app = NSWorkspace.shared.frontmostApplication
    emit(["pid": app?.processIdentifier ?? 0, "name": app?.localizedName ?? "", "bundle": app?.bundleIdentifier ?? ""])

case "activate":
    // probe activate <pid>
    setFrontmost(pidArg(0))
    sleepMs(300)
    let app = NSWorkspace.shared.frontmostApplication
    emit(["pid": app?.processIdentifier ?? 0, "name": app?.localizedName ?? ""])

case "hotkey":
    // probe hotkey [--count N] [--gap-ms M]   (Ctrl+Option+P, ontop's default chord)
    let count = option("--count").flatMap(Int.init) ?? 1
    let gap = option("--gap-ms").flatMap(Int.init) ?? 0
    for i in 0..<count {
        postKey(35, flags: [.maskControl, .maskAlternate])
        if i < count - 1 { sleepMs(gap) }
    }
    emit(["pressed": count, "gapMs": gap])

case "space":
    // probe space left|right — Mission Control's Ctrl+Arrow, waits for the switch
    let dir = positional(0, "left or right")
    let before = activeSpace()
    postKey(dir == "left" ? 123 : 124, flags: [.maskControl, .maskSecondaryFn, .maskNumericPad])
    var after = before
    for _ in 0..<40 {
        sleepMs(50)
        after = activeSpace()
        if after != before { break }
    }
    sleepMs(700) // the switch animation; windows report their final state after it
    let (all, _) = desktops()
    emit(["switched": after != before, "from": all.first { $0.space == before }.map(desktopJSON) ?? [:],
          "to": all.first { $0.space == after }.map(desktopJSON) ?? [:]])

case "desktops":
    let (all, current) = desktops()
    let active = activeSpace()
    emit(["active": all.first { $0.space == active }.map(desktopJSON) ?? ["space": active],
          "current": current.mapValues { s in all.first { $0.space == s }?.index ?? 0 },
          "all": all.map(desktopJSON)])

case "menu":
    // probe menu list <pid> | probe menu click <pid> <title> [--section APP]
    let sub = positional(0, "list or click")
    let pid = pidArg(1)
    let menu = openMenu(pid: pid)
    if sub == "list" {
        let items = menuItems(menu)
        closeMenu(menu, pid: pid)
        emit(items)
    } else if sub == "click" {
        let title = positional(2, "item title")
        let section = option("--section")
        let items = axChildren(menu)
        let rows = menuItems(menu)
        guard let i = rows.indices.first(where: { rows[$0]["title"] as? String == title && (section == nil || rows[$0]["section"] as? String == section) }) else {
            closeMenu(menu, pid: pid)
            fail("no menu item \"\(title)\"\(section.map { " under \($0)" } ?? "")")
        }
        AXUIElementSetMessagingTimeout(items[i], 1)
        AXUIElementPerformAction(items[i], kAXPressAction as CFString)
        // "Quit ontop" takes the status item with it; there is no menu left to wait for.
        if title != "Quit ontop" { waitMenuClosed(pid: pid) }
        emit(["clicked": title, "wasChecked": rows[i]["checked"] as? Bool ?? false, "section": rows[i]["section"] as? String ?? ""])
    } else {
        fail("menu: unknown subcommand \(sub)")
    }

case "click":
    // probe click <x> <y>   global top-left coordinates, as CGWindowList bounds
    guard let x = Double(positional(0, "x")), let y = Double(positional(1, "y")) else { fail("x and y must be numbers") }
    let point = CGPoint(x: x, y: y)
    // Report what is on top at that point before clicking, so the evidence says what was hit.
    let top = windowList(all: false).first { info in
        guard (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
        return CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!).contains(point)
    }
    postClick(point)
    emit(["clicked": [x, y], "topWindowBeforeClick": top.map(windowJSON) ?? [:]])

case "ax-windows":
    // probe ax-windows <pid>
    let app = AXUIElementCreateApplication(pidArg(0))
    let focused = axElement(app, kAXFocusedWindowAttribute)
    emit(axChildren(app, kAXWindowsAttribute).map { w in
        let f = axFrame(w) ?? .zero
        return ["title": axString(w, kAXTitleAttribute) ?? "", "subrole": axString(w, kAXSubroleAttribute) ?? "",
                "frame": [f.minX, f.minY, f.width, f.height], "focused": focused.map { CFEqual($0, w) } ?? false]
    })

case "ax-place":
    // probe ax-place <pid> <title> <x> <y> <w> <h>
    let w = axWindow(pid: pidArg(0), title: positional(1, "title"))
    let nums = (2...5).map { Double(positional($0, "frame")) ?? 0 }
    var origin = CGPoint(x: nums[0], y: nums[1]), size = CGSize(width: nums[2], height: nums[3])
    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!)
    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
    sleepMs(200)
    let f = axFrame(w) ?? .zero
    emit(["frame": [f.minX, f.minY, f.width, f.height]])

case "ax-raise":
    // probe ax-raise <pid> <title> — the window to the front of its app, the app to the front
    let pid = pidArg(0)
    let w = axWindow(pid: pid, title: positional(1, "title"))
    AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
    setFrontmost(pid)
    sleepMs(300)
    emit(["front": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0])

case "ax-close":
    // probe ax-close <pid> <title>
    let w = axWindow(pid: pidArg(0), title: positional(1, "title"))
    guard let button = axElement(w, kAXCloseButtonAttribute) else { fail("window has no close button") }
    AXUIElementPerformAction(button, kAXPressAction as CFString)
    emit(["closed": positional(1, "title")])

case "ax-caret":
    // probe ax-caret <pid> <title> — insertion point of the window's text area
    let w = axWindow(pid: pidArg(0), title: positional(1, "title"))
    guard let text = findDescendant(w, role: kAXTextAreaRole) else { fail("no text area in window") }
    var range = CFRange(location: -1, length: 0)
    if let raw = axValue(text, kAXSelectedTextRangeAttribute) { AXValueGetValue(raw as! AXValue, .cfRange, &range) }
    emit(["location": range.location, "length": range.length])

case "opaque":
    // probe opaque <png> — share of non-transparent pixels, to tell a mirror frame from an empty one
    let path = positional(0, "png")
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(path)") }
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var opaque = 0
    for i in stride(from: 3, to: pixels.count, by: 4) where pixels[i] > 8 { opaque += 1 }
    emit(["width": w, "height": h, "opaque": Double(opaque) / Double(max(1, w * h))])

case "quit":
    // probe quit <pid> — the polite quit an app gets from the Dock or Cmd+Q
    guard let app = NSRunningApplication(processIdentifier: pidArg(0)) else { fail("no app with that pid") }
    emit(["terminateSent": app.terminate()])

case "cover":
    // probe cover <x> <y> <w> <h> [--title T]   blocks; kill its pid to end it
    let nums = (0...3).map { Double(positional($0, "rect")) ?? 0 }
    let app = NSApplication.shared
    let delegate = CoverDelegate(rect: CGRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3]),
                                 title: option("--title") ?? "ontop-verify cover")
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()

default:
    fail("unknown command \(command)")
}
