import AppKit
import ScreenCaptureKit

/// M0 spike: pins the first iTerm2 window at launch. Menu, hotkey and window picking come
/// in later milestones.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let spikeBundleID = "com.googlecode.iterm2"

    private var statusItem: NSStatusItem?
    private var pin: Pin?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        guard Permissions.ensureAccessibility() else {
            Log.app.error("Accessibility not granted; grant it in Privacy & Security, then relaunch")
            return
        }
        guard Permissions.ensureScreenRecording() else {
            Log.app.error("Screen Recording not granted; grant it in Privacy & Security, then relaunch")
            return
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        Task { await pinSpikeWindow() }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "ontop")
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit ontop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func pinSpikeWindow() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: {
                $0.owningApplication?.bundleIdentifier == Self.spikeBundleID
                    && $0.windowLayer == 0
                    && !($0.title ?? "").isEmpty
            }) else {
                Log.app.error("no iTerm2 window on screen")
                return
            }
            guard let target = TargetWindow(scWindow: window) else {
                Log.app.error("could not track window \(window.windowID)")
                return
            }
            let pin = Pin(target: target)
            pin.onGone = { [weak self] in
                Log.app.info("unpinned")
                self?.pin = nil
            }
            self.pin = pin
            Log.app.info("pinned \(window.title ?? "", privacy: .public) (\(window.windowID)) frame \(window.frame.debugDescription, privacy: .public)")
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.pid {
                pin.show()
            }
        } catch {
            Log.app.error("shareable content: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func applicationActivated(_ note: Notification) {
        guard let pin,
              let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        if app.processIdentifier == pin.target.pid {
            pin.hide()
        } else if app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            pin.show()
        }
    }
}
