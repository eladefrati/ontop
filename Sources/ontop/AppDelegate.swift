import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var manager: PinManager?
    private var hotKey: HotKey?
    private var statusMenu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await start() }
    }

    private func start() async {
        // A process that is about to relaunch builds nothing: no second icon, no hotkey race.
        guard await Onboarding.ensurePermissions() == .ready else {
            Onboarding.relaunch()
            return
        }
        let manager = PinManager()
        let hotKey = HotKey()
        hotKey.onPress = { manager.pinFrontmostWindow() }
        do {
            try hotKey.register(Settings.chord)
        } catch {
            Log.app.error("hotkey \(Settings.chord.display) unavailable: \(String(describing: error))")
        }
        self.manager = manager
        self.hotKey = hotKey
        self.statusMenu = StatusMenu(manager: manager, hotKey: hotKey)
    }
}
