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

    func toggleWindow(anchorRect: NSRect? = nil) {
        guard let window else { return }
        _ = anchorRect

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

        let finalFrame = displayTarget.resolve()?.frame ?? window.frame
        let startFrame = finalFrame.insetBy(dx: finalFrame.width * 0.018, dy: finalFrame.height * 0.028)
        window.setFrame(startFrame, display: true)
        window.contentView?.alphaValue = 1

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(finalFrame, display: true)
        }
    }

    private func animateOut(window: NSWindow) {
        let currentFrame = window.frame
        let targetFrame = currentFrame.insetBy(dx: currentFrame.width * 0.015, dy: currentFrame.height * 0.022)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
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

    override func close() {
        if isVisible, let controller = windowController as? LaunchDeckShellWindowController {
            controller.toggleWindow(anchorRect: nil)
            return
        }
        super.close()
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
