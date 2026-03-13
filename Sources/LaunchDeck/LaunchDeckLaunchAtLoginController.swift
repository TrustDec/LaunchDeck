import Foundation
import ServiceManagement

@MainActor
final class LaunchDeckLaunchAtLoginController {
    static let shared = LaunchDeckLaunchAtLoginController()

    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func toggle() {
        guard #available(macOS 13.0, *) else {
            return
        }

        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            LaunchDeckDiagnostics.log("launch at login toggle failed: \(error.localizedDescription)")
        }
    }
}
