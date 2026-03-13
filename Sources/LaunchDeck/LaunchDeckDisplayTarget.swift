import AppKit

enum LaunchDeckDisplayTarget {
    case cursor
    case primary
    case main
    case index(Int)

    static func developmentDefault(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> LaunchDeckDisplayTarget {
        if environment["LAUNCHDECK_DISPLAY"] != nil {
            return fromEnvironment(environment)
        }

        #if DEBUG
        return .index(1)
        #else
        return .cursor
        #endif
    }

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> LaunchDeckDisplayTarget {
        guard let rawValue = environment["LAUNCHDECK_DISPLAY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !rawValue.isEmpty else {
            return .cursor
        }

        switch rawValue {
        case "cursor", "mouse":
            return .cursor
        case "primary":
            return .primary
        case "main":
            return .main
        default:
            if let index = Int(rawValue) {
                return .index(index)
            }

            return .cursor
        }
    }

    func resolve() -> NSScreen? {
        switch self {
        case .cursor:
            return screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        case .primary:
            return NSScreen.screens.first ?? NSScreen.main
        case .main:
            return NSScreen.main ?? NSScreen.screens.first
        case let .index(index):
            guard index >= 0, index < NSScreen.screens.count else {
                return NSScreen.main ?? NSScreen.screens.first
            }

            return NSScreen.screens[index]
        }
    }

    private func screenContainingMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(location)
        }
    }
}
