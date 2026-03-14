import AppKit
import SwiftUI

@main
struct LaunchDeckApp: App {
    @NSApplicationDelegateAdaptor(LaunchDeckAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class LaunchDeckAppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: LaunchDeckShellWindowController?
    private var statusItemController: LaunchDeckStatusItemController?
    private let persistence = LaunchDeckPersistenceController()
    private lazy var store = LaunchDeckShellStore(persistence: persistence)
    private let displayTarget = LaunchDeckDisplayTarget.developmentDefault()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchDeckDockIntegrationController.shared.applyActivationPolicy()
        LaunchDeckDiagnostics.log("applicationDidFinishLaunching displayTarget=\(String(describing: displayTarget))")
        let controller = LaunchDeckShellWindowController(store: store, displayTarget: displayTarget)
        LaunchDeckDiagnostics.log("windowController initialized")
        controller.toggleWindow(anchorRect: nil)
        LaunchDeckDiagnostics.log("initial animated presentation dispatched")
        windowController = controller
        LaunchDeckHotKeyMonitor.shared.start { [weak controller] in
            controller?.toggleWindow(anchorRect: nil)
        }
        LaunchDeckHotCornersMonitor.shared.start { [weak controller] in
            controller?.toggleWindow(anchorRect: nil)
        }
        statusItemController = LaunchDeckStatusItemController(
            onToggle: { [weak controller] anchorRect in
                controller?.toggleWindow(anchorRect: anchorRect)
            },
            onReload: { [weak self] in
                self?.store.reloadFromUI()
            },
            onResetLayout: { [weak self] in
                self?.store.resetLayoutFromSystem()
            },
            onToggleCompactMode: { [weak self] in
                self?.store.toggleCompactMode()
            },
            onToggleDockIcon: {
                LaunchDeckDockIntegrationController.shared.toggleDockIconVisibility()
            },
            hiddenItemsProvider: { [weak self] in
                self?.store.hiddenItems ?? []
            },
            onRestoreHiddenItem: { [weak self] id in
                self?.store.restoreHiddenItem(id: id)
            },
            onRestoreAllHiddenItems: { [weak self] in
                self?.store.restoreAllHiddenItems()
            },
            onSelectHotCorner: { corner in
                LaunchDeckHotCornersMonitor.shared.selectedCorner = corner
            }
        )
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let toggle = NSMenuItem(title: "Toggle LaunchDeck", action: #selector(toggleLaunchDeckFromDockMenu), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let reload = NSMenuItem(title: "Reload Apps", action: #selector(reloadAppsFromDockMenu), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)

        let showDockIcon = NSMenuItem(title: "Show Dock Icon", action: #selector(toggleDockIconFromDockMenu), keyEquivalent: "")
        showDockIcon.state = LaunchDeckDockIntegrationController.shared.showsDockIcon ? .on : .off
        showDockIcon.target = self
        menu.addItem(showDockIcon)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit LaunchDeck", action: #selector(quitFromDockMenu), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        LaunchDeckDiagnostics.log("applicationDidBecomeActive")
        NSApp.presentationOptions = LaunchDeckDockIntegrationController.shared.showsDockIcon
            ? [.hideMenuBar]
            : [.hideDock, .hideMenuBar]
        windowController?.window?.makeKeyAndOrderFront(self)
    }

    func applicationWillResignActive(_ notification: Notification) {
        LaunchDeckDiagnostics.log("applicationWillResignActive")
        NSApp.presentationOptions = []
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc
    private func toggleLaunchDeckFromDockMenu() {
        windowController?.toggleWindow(anchorRect: nil)
    }

    @objc
    private func reloadAppsFromDockMenu() {
        store.reloadFromUI()
    }

    @objc
    private func toggleDockIconFromDockMenu() {
        LaunchDeckDockIntegrationController.shared.toggleDockIconVisibility()
    }

    @objc
    private func quitFromDockMenu() {
        NSApp.terminate(nil)
    }
}
