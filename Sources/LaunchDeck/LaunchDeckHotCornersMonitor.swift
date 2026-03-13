import AppKit
import Foundation

@MainActor
final class LaunchDeckHotCornersMonitor {
    enum Corner: String, CaseIterable {
        case disabled
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        var title: String {
            switch self {
            case .disabled: "Disabled"
            case .topLeft: "Top Left"
            case .topRight: "Top Right"
            case .bottomLeft: "Bottom Left"
            case .bottomRight: "Bottom Right"
            }
        }
    }

    static let shared = LaunchDeckHotCornersMonitor()

    private enum DefaultsKey {
        static let selectedCorner = "LaunchDeck.selectedHotCorner"
    }

    private var timer: Timer?
    private var isInsideActiveCorner = false
    private var lastTriggerDate = Date.distantPast
    private var action: (() -> Void)?

    var selectedCorner: Corner {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: DefaultsKey.selectedCorner),
                  let corner = Corner(rawValue: rawValue)
            else {
                return .disabled
            }
            return corner
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: DefaultsKey.selectedCorner)
            isInsideActiveCorner = false
        }
    }

    func start(action: @escaping () -> Void) {
        self.action = action
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPointer()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func pollPointer() {
        guard selectedCorner != .disabled else {
            isInsideActiveCorner = false
            return
        }

        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) else {
            isInsideActiveCorner = false
            return
        }

        let hotspot = hotspotRect(for: selectedCorner, in: screen.frame)
        let isInside = hotspot.contains(pointer)

        defer { isInsideActiveCorner = isInside }

        guard isInside, !isInsideActiveCorner else {
            return
        }

        guard Date().timeIntervalSince(lastTriggerDate) > 0.8 else {
            return
        }

        lastTriggerDate = Date()
        action?()
    }

    private func hotspotRect(for corner: Corner, in frame: NSRect) -> NSRect {
        let size: CGFloat = 6

        switch corner {
        case .disabled:
            return .zero
        case .topLeft:
            return NSRect(x: frame.minX, y: frame.maxY - size, width: size, height: size)
        case .topRight:
            return NSRect(x: frame.maxX - size, y: frame.maxY - size, width: size, height: size)
        case .bottomLeft:
            return NSRect(x: frame.minX, y: frame.minY, width: size, height: size)
        case .bottomRight:
            return NSRect(x: frame.maxX - size, y: frame.minY, width: size, height: size)
        }
    }
}
