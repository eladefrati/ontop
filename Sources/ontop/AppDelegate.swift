import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owns the manager and the hotkey through its mode, once onboarding is done.
    private var statusMenu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The icon and Quit come first, whatever onboarding waits for.
        let statusMenu = StatusMenu()
        self.statusMenu = statusMenu
        Task { await start(statusMenu) }
    }

    private func start(_ statusMenu: StatusMenu) async {
        await Onboarding.run(onWaiting: { statusMenu.mode = .waiting($0) })
        let manager = PinManager()
        let hotKey = HotKey(onPress: { manager.pinFrontmostWindow() })
        statusMenu.mode = .ready(manager, hotKey)
    }
}
