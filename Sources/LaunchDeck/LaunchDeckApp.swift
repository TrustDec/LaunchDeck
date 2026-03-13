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
    private var windowController: LaunchDeckWindowController?
    private let store = LaunchDeckStore()
    private let displayTarget = LaunchDeckDisplayTarget.developmentDefault()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchDeckDiagnostics.log("applicationDidFinishLaunching displayTarget=\(String(describing: displayTarget))")
        let controller = LaunchDeckWindowController(store: store, displayTarget: displayTarget)
        LaunchDeckDiagnostics.log("windowController initialized")
        controller.showWindow(self)
        LaunchDeckDiagnostics.log("showWindow dispatched")
        controller.window?.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
        windowController = controller
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        LaunchDeckDiagnostics.log("applicationDidBecomeActive")
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        windowController?.window?.makeKeyAndOrderFront(self)
    }

    func applicationWillResignActive(_ notification: Notification) {
        LaunchDeckDiagnostics.log("applicationWillResignActive")
        NSApp.presentationOptions = []
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
