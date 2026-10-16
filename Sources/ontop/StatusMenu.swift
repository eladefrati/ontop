import AppKit

/// The menu bar item and its menu: pinned state per window, grouped by app.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let manager: PinManager
    private let item: NSStatusItem
    private let menu = NSMenu()

    init(manager: PinManager) {
        self.manager = manager
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "ontop")
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        manager.onChange = { [weak self] in self?.updateIcon() }
        updateIcon()
    }

    // Rebuilt every time it opens, so the window list is current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let pinFront = NSMenuItem(title: "Pin Frontmost Window", action: #selector(pinFrontmost), keyEquivalent: "")
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
        manager.pinFrontmostWindow()
    }

    @objc private func toggleWindow(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.uint32Value else { return }
        manager.toggle(id)
    }

    @objc private func unpinAll() {
        manager.unpinAll()
    }
}
