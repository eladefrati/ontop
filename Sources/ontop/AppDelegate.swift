import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var manager: PinManager?
    private var statusMenu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Permissions.ensureAccessibility() else {
            Log.app.error("Accessibility not granted; grant it in Privacy & Security, then relaunch")
            return
        }
        guard Permissions.ensureScreenRecording() else {
            Log.app.error("Screen Recording not granted; grant it in Privacy & Security, then relaunch")
            return
        }
        let manager = PinManager()
        self.manager = manager
        self.statusMenu = StatusMenu(manager: manager)
    }
}
