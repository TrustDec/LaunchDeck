import AppKit

@MainActor
final class LaunchDeckStatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var contextMenu = NSMenu()
    private let onToggle: () -> Void
    private let onReload: () -> Void
    private let onResetLayout: () -> Void
    private let onToggleCompactMode: () -> Void
    private let onToggleDockIcon: () -> Void
    private let hiddenItemsProvider: () -> [LaunchItem]
    private let onRestoreHiddenItem: (UUID) -> Void
    private let onRestoreAllHiddenItems: () -> Void
    private let onSelectHotCorner: (LaunchDeckHotCornersMonitor.Corner) -> Void

    init(
        onToggle: @escaping () -> Void,
        onReload: @escaping () -> Void,
        onResetLayout: @escaping () -> Void,
        onToggleCompactMode: @escaping () -> Void,
        onToggleDockIcon: @escaping () -> Void,
        hiddenItemsProvider: @escaping () -> [LaunchItem],
        onRestoreHiddenItem: @escaping (UUID) -> Void,
        onRestoreAllHiddenItems: @escaping () -> Void,
        onSelectHotCorner: @escaping (LaunchDeckHotCornersMonitor.Corner) -> Void
    ) {
        self.onToggle = onToggle
        self.onReload = onReload
        self.onResetLayout = onResetLayout
        self.onToggleCompactMode = onToggleCompactMode
        self.onToggleDockIcon = onToggleDockIcon
        self.hiddenItemsProvider = hiddenItemsProvider
        self.onRestoreHiddenItem = onRestoreHiddenItem
        self.onRestoreAllHiddenItems = onRestoreAllHiddenItems
        self.onSelectHotCorner = onSelectHotCorner
        super.init()
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "LaunchDeck")
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Reload Apps", action: #selector(reloadApps), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reset Layout", action: #selector(resetLayout), keyEquivalent: ""))
        menu.addItem(compactModeMenuItem())
        menu.addItem(showDockIconMenuItem())
        menu.addItem(launchAtLoginMenuItem())
        menu.addItem(hiddenItemsMenuItem())
        menu.addItem(hotCornerMenuItem())
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LaunchDeck", action: #selector(quitApp), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        contextMenu = menu
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            onToggle()
            return
        }

        let isRightClick = event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        if isRightClick {
            statusItem.menu = contextMenu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            onToggle()
        }
    }

    @objc
    private func reloadApps() {
        onReload()
    }

    @objc
    private func resetLayout() {
        onResetLayout()
    }

    @objc
    private func toggleCompactMode() {
        onToggleCompactMode()
        configure()
    }

    @objc
    private func toggleDockIcon() {
        onToggleDockIcon()
        configure()
    }

    @objc
    private func toggleLaunchAtLogin() {
        LaunchDeckLaunchAtLoginController.shared.toggle()
        configure()
    }

    @objc
    private func restoreHiddenItem(_ sender: NSMenuItem) {
        guard let uuidString = sender.representedObject as? String,
              let id = UUID(uuidString: uuidString)
        else {
            return
        }

        onRestoreHiddenItem(id)
        configure()
    }

    @objc
    private func restoreAllHiddenItems() {
        onRestoreAllHiddenItems()
        configure()
    }

    @objc
    private func selectHotCorner(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let corner = LaunchDeckHotCornersMonitor.Corner(rawValue: rawValue)
        else {
            return
        }

        onSelectHotCorner(corner)
        configure()
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }

    private func hotCornerMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Hot Corner", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let selectedCorner = LaunchDeckHotCornersMonitor.shared.selectedCorner

        for corner in LaunchDeckHotCornersMonitor.Corner.allCases {
            let option = NSMenuItem(title: corner.title, action: #selector(selectHotCorner(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = corner.rawValue
            option.state = corner == selectedCorner ? .on : .off
            submenu.addItem(option)
        }

        item.submenu = submenu
        return item
    }

    private func compactModeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Compact Mode", action: #selector(toggleCompactMode), keyEquivalent: "")
        item.state = UserDefaults.standard.bool(forKey: "LaunchDeck.compactMode") ? .on : .off
        item.target = self
        return item
    }

    private func launchAtLoginMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Launch At Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        item.state = LaunchDeckLaunchAtLoginController.shared.isEnabled ? .on : .off
        item.target = self
        return item
    }

    private func showDockIconMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Show Dock Icon", action: #selector(toggleDockIcon), keyEquivalent: "")
        item.state = LaunchDeckDockIntegrationController.shared.showsDockIcon ? .on : .off
        item.target = self
        return item
    }

    private func hiddenItemsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Hidden Apps", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let hiddenItems = hiddenItemsProvider()

        if hiddenItems.isEmpty {
            let empty = NSMenuItem(title: "No Hidden Apps", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            let restoreAll = NSMenuItem(title: "Restore All", action: #selector(restoreAllHiddenItems), keyEquivalent: "")
            restoreAll.target = self
            submenu.addItem(restoreAll)
            submenu.addItem(.separator())

            for item in hiddenItems {
                let option = NSMenuItem(title: item.title, action: #selector(restoreHiddenItem(_:)), keyEquivalent: "")
                option.target = self
                option.representedObject = item.id.uuidString
                submenu.addItem(option)
            }
        }

        item.submenu = submenu
        return item
    }
}
