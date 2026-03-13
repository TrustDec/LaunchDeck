import AppKit
import Foundation

@MainActor
final class LaunchDeckDockIntegrationController {
    private enum DefaultsKey {
        static let showDockIcon = "LaunchDeck.showDockIcon"
    }

    static let shared = LaunchDeckDockIntegrationController()

    var showsDockIcon: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.showDockIcon) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.showDockIcon) }
    }

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(showsDockIcon ? .regular : .accessory)
    }

    func toggleDockIconVisibility() {
        showsDockIcon.toggle()
        applyActivationPolicy()
    }
}
