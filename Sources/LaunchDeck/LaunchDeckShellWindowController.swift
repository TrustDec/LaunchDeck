import AppKit
import SwiftUI

final class LaunchDeckShellWindowController: NSWindowController {
    private let displayTarget: LaunchDeckDisplayTarget

    init(store: LaunchDeckShellStore, displayTarget: LaunchDeckDisplayTarget) {
        self.displayTarget = displayTarget

        let screenFrame = displayTarget.resolve()?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let hostingView = NSHostingView(rootView: LaunchDeckShellView(store: store))

        let window = LaunchDeckShellWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.setFrame(screenFrame, display: true)
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .stationary, .ignoresCycle]
        window.level = .mainMenu
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.hasShadow = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func toggleWindow() {
        guard let window else { return }

        if window.isVisible {
            animateOut(window: window)
        } else {
            showWindow(nil)
            animateIn(window: window)
        }
    }

    private func animateIn(window: NSWindow) {
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let finalFrame = window.frame
        let insetFrame = finalFrame.insetBy(dx: 42, dy: 24)
        window.setFrame(insetFrame, display: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(finalFrame, display: true)
        }
    }

    private func animateOut(window: NSWindow) {
        let currentFrame = window.frame
        let targetFrame = currentFrame.insetBy(dx: 42, dy: 24)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
            window.animator().setFrame(targetFrame, display: true)
        }, completionHandler: {
            Task { @MainActor in
                window.orderOut(nil)
                window.alphaValue = 1
                window.setFrame(currentFrame, display: true)
            }
        })
    }
}

final class LaunchDeckShellWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }
}
