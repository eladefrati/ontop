import AppKit
import ServiceManagement

/// The menu bar item and its menu. It exists from launch, so Quit is always there; what the
/// menu offers follows `mode`.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    enum Mode {
        /// Onboarding has not reported yet: the footer only.
        case starting
        /// A permission is missing: what and why, a way to grant it, and the footer.
        case waiting(Permission)
        /// Pinned state per window, grouped by app, and the settings.
        case ready(PinManager, HotKey)
    }

    var mode: Mode = .starting {
        didSet {
            if case .ready(let manager, _) = mode {
                manager.onChange = { [weak self] in self?.updateIcon() }
                // The reason waits in the menu's first line.
                manager.onFailure = { NSSound.beep() }
            }
            updateIcon()
        }
    }

    private var item: NSStatusItem
    private let menu = NSMenu()
    private var recorder: ChordRecorderWindow?

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        updateIcon()
    }

    // Rebuilt every time it opens, so the window list is current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        switch mode {
        case .starting:
            break
        case .waiting(let permission):
            for item in Self.waitingItems(permission, target: self) { menu.addItem(item) }
        case .ready(let manager, let hotKey):
            addReady(manager, hotKey)
        }
        for item in Self.footer() { menu.addItem(item) }
    }

    /// While a permission is missing: what is missing and why, and a way to grant it. macOS
    /// shows its own prompt once; this menu is ontop's explanation. For Screen Recording it
    /// also offers a relaunch, since a running process never sees that grant.
    static func waitingItems(_ permission: Permission, target: AnyObject?) -> [NSMenuItem] {
        let missing = NSMenuItem(title: permission.title, action: nil, keyEquivalent: "")
        missing.subtitle = permission.reason
        missing.isEnabled = false
        let open = NSMenuItem(title: "Open System Settings\u{2026}", action: #selector(openPermissionSettings), keyEquivalent: "")
        open.target = target
        guard permission == .screenRecording else { return [missing, open, .separator()] }
        let relaunch = NSMenuItem(title: "Relaunch ontop", action: #selector(relaunch), keyEquivalent: "")
        relaunch.target = target
        return [missing, open, relaunch, .separator()]
    }

    /// The version and Quit, in every mode.
    private static func footer() -> [NSMenuItem] {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let about = NSMenuItem(title: "ontop \(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        return [about, NSMenuItem(title: "Quit ontop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")]
    }

    private func addReady(_ manager: PinManager, _ hotKey: HotKey) {
        if let failure = manager.failure {
            let reason = NSMenuItem(title: failure.message, action: nil, keyEquivalent: "")
            reason.isEnabled = false
            menu.addItem(reason)
        }
        let chord = hotKey.chord
        let pinFront = NSMenuItem(title: "Pin Frontmost Window", action: #selector(pinFrontmost), keyEquivalent: chord.keyEquivalent)
        pinFront.keyEquivalentModifierMask = chord.flags
        pinFront.target = self
        menu.addItem(pinFront)
        menu.addItem(.separator())

        let windows = WindowList.onScreen()
        if windows.isEmpty {
            let none = NSMenuItem(title: "No Windows", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for (appName, group) in Self.groupedByApp(windows) {
            let header = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for window in group {
                let entry = NSMenuItem(title: window.title, action: #selector(toggleWindow(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = window
                entry.indentationLevel = 1
                entry.state = manager.isPinned(window.id) ? .on : .off
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        let unpinAll = NSMenuItem(title: "Unpin All", action: #selector(unpinAll), keyEquivalent: "")
        unpinAll.target = self
        unpinAll.isEnabled = manager.hasPins
        menu.addItem(unpinAll)
        menu.addItem(.separator())

        let launch = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = Self.launchAtLoginState(SMAppService.mainApp.status)
        menu.addItem(launch)
        let follow = NSMenuItem(title: "Follow Across Desktops", action: #selector(toggleFollowsDesktops), keyEquivalent: "")
        follow.target = self
        follow.state = manager.followsDesktops ? .on : .off
        menu.addItem(follow)
        let shortcut = NSMenuItem(title: "Change Shortcut\u{2026}", action: #selector(changeShortcut), keyEquivalent: "")
        shortcut.target = self
        menu.addItem(shortcut)
        menu.addItem(.separator())
    }

    /// Apps in order of their frontmost window; windows in front-to-back order within each.
    static func groupedByApp(_ windows: [WindowInfo]) -> [(String, [WindowInfo])] {
        var order: [String] = []
        var groups: [String: [WindowInfo]] = [:]
        for window in windows {
            if groups[window.appName] == nil { order.append(window.appName) }
            groups[window.appName, default: []].append(window)
        }
        return order.map { ($0, groups[$0]!) }
    }

    /// A check mark when enabled, a dash while macOS waits for the user to approve the login
    /// item in System Settings, nothing otherwise.
    static func launchAtLoginState(_ status: SMAppService.Status) -> NSControl.StateValue {
        switch status {
        case .enabled: .on
        case .requiresApproval: .mixed
        default: .off
        }
    }

    private func updateIcon() {
        let name = switch mode {
        case .starting: "pin"
        case .waiting: "pin.slash"
        case .ready(let manager, _): manager.hasPins ? "pin.fill" : "pin"
        }
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "ontop")
    }

    private var manager: PinManager? {
        if case .ready(let manager, _) = mode { manager } else { nil }
    }

    @objc private func openPermissionSettings() {
        guard case .waiting(let permission) = mode else { return }
        NSWorkspace.shared.open(permission.settingsURL)
    }

    // The icon goes first, so the menu bar never shows two icons. If the new instance does not
    // start, this one keeps running and the icon comes back with the same menu.
    @objc private func relaunch() {
        NSStatusBar.system.removeStatusItem(item)
        Onboarding.relaunch(onFailure: { [weak self] in
            guard let self else { return }
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.menu = menu
            updateIcon()
        })
    }

    @objc private func pinFrontmost() {
        // The shortcut shown on this item is also the global hot key, which fires for the
        // same press; let the hot key handle keyboard activation so the pin toggles once.
        guard NSApp.currentEvent?.type != .keyDown else { return }
        manager?.pinFrontmostWindow()
    }

    @objc private func toggleWindow(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? WindowInfo else { return }
        manager?.toggle(window)
    }

    @objc private func unpinAll() {
        manager?.unpinAll()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            case .requiresApproval:
                // Only the user can approve it, in System Settings > Login Items.
                SMAppService.openSystemSettingsLoginItems()
            default:
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            Log.app.error("launch at login: \(error.localizedDescription)")
            Self.alert("Could not change Launch at Login", error.localizedDescription)
        }
    }

    @objc private func toggleFollowsDesktops() {
        manager?.followsDesktops.toggle()
    }

    @objc private func changeShortcut() {
        guard case .ready(_, let hotKey) = mode else { return }
        let window = ChordRecorderWindow(current: hotKey.chord)
        recorder = window
        window.present { [weak self] chord in
            guard let self else { return }
            self.recorder = nil
            guard let chord else { return }
            do {
                try hotKey.change(to: chord)
            } catch HotKey.RegistrationError.inUse {
                Self.alert("Shortcut in use", "\(chord.display) is already taken by another app. The shortcut stays \(hotKey.chord.display).")
            } catch {
                Self.alert("Could not set shortcut", String(describing: error))
            }
        }
    }

    private static func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }
}
