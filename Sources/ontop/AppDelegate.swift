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
        switch await Onboarding.run(onWaiting: { statusMenu.mode = .waiting($0) }) {
        case .relaunch:
            // A process that is about to relaunch builds nothing, and its icon goes first, so
            // the menu bar never shows two icons and two processes never race for the hotkey.
            statusMenu.remove()
            Onboarding.relaunch()
        case .ready:
            let manager = PinManager()
            let hotKey = HotKey(onPress: { manager.pinFrontmostWindow() })
            statusMenu.mode = .ready(manager, hotKey)
        }
    }
}
