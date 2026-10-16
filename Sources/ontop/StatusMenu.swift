import AppKit
import ServiceManagement

/// The menu bar item and its menu: pinned state per window, grouped by app.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let manager: PinManager
    private let hotKey: HotKey
    private let item: NSStatusItem
    private let menu = NSMenu()
    private var recorder: ChordRecorderWindow?

    init(manager: PinManager, hotKey: HotKey) {
        self.manager = manager
        self.hotKey = hotKey
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        manager.onChange = { [weak self] in self?.updateIcon() }
        updateIcon()
    }

    // Rebuilt every time it opens, so the window list is current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let chord = Settings.chord
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
                entry.representedObject = NSNumber(value: window.id)
                entry.indentationLevel = 1
                entry.state = manager.isPinned(window.id) ? .on : .off
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        let unpinAll = NSMenuItem(title: "Unpin All", action: #selector(unpinAll), keyEquivalent: "")
        unpinAll.target = self
        unpinAll.isEnabled = !manager.pins.isEmpty
        menu.addItem(unpinAll)
        menu.addItem(.separator())

        let launch = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launch)
        let shortcut = NSMenuItem(title: "Change Shortcut\u{2026}", action: #selector(changeShortcut), keyEquivalent: "")
        shortcut.target = self
        menu.addItem(shortcut)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ontop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// Apps in order of their frontmost window; windows in front-to-back order within each.
    private static func groupedByApp(_ windows: [WindowInfo]) -> [(String, [WindowInfo])] {
        var order: [String] = []
        var groups: [String: [WindowInfo]] = [:]
        for window in windows {
            if groups[window.appName] == nil { order.append(window.appName) }
            groups[window.appName, default: []].append(window)
        }
        return order.map { ($0, groups[$0]!) }
    }

    private func updateIcon() {
        let name = manager.pins.isEmpty ? "pin" : "pin.fill"
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "ontop")
    }

    @objc private func pinFrontmost() {
        // The shortcut shown on this item is also the global hot key, which fires for the
        // same press; let the hot key handle keyboard activation so the pin toggles once.
        guard NSApp.currentEvent?.type != .keyDown else { return }
        manager.pinFrontmostWindow()
    }

    @objc private func toggleWindow(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.uint32Value else { return }
        manager.toggle(id)
    }

    @objc private func unpinAll() {
        manager.unpinAll()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.app.error("launch at login: \(error.localizedDescription)")
            Self.alert("Could not change Launch at Login", error.localizedDescription)
        }
    }

    @objc private func changeShortcut() {
        let window = ChordRecorderWindow(current: Settings.chord)
        recorder = window
        window.present { [weak self] chord in
            guard let self else { return }
            self.recorder = nil
            guard let chord, chord != Settings.chord else { return }
            let previous = Settings.chord
            do {
                try self.hotKey.register(chord)
                Settings.chord = chord
            } catch HotKey.RegistrationError.inUse {
                try? self.hotKey.register(previous)
                Self.alert("Shortcut in use", "\(chord.display) is already taken by another app. The shortcut stays \(previous.display).")
            } catch {
                try? self.hotKey.register(previous)
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
