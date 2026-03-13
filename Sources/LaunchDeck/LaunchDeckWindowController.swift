import AppKit
import SwiftUI

final class LaunchDeckWindowController: NSWindowController {
    private let displayTarget: LaunchDeckDisplayTarget

    init(store: LaunchDeckStore, displayTarget: LaunchDeckDisplayTarget) {
        self.displayTarget = displayTarget

        let screenFrame = displayTarget.resolve()?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        LaunchDeckDiagnostics.log("windowController init screenFrame=\(Int(screenFrame.width))x\(Int(screenFrame.height))")
        let contentView = LaunchDeckView(store: store)
        let hostingView = NSHostingView(rootView: contentView)

        let window = LaunchDeckWindow(
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

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)

        guard let window else {
            LaunchDeckDiagnostics.log("showWindow aborted because window=nil")
            return
        }

        let finalFrame = displayTarget.resolve()?.frame ?? window.frame
        let startFrame = finalFrame.insetBy(dx: finalFrame.width * 0.015, dy: finalFrame.height * 0.015)
        LaunchDeckDiagnostics.log("showWindow frame start=\(Int(startFrame.width))x\(Int(startFrame.height)) final=\(Int(finalFrame.width))x\(Int(finalFrame.height))")
        window.alphaValue = 0
        window.setFrame(startFrame, display: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(finalFrame, display: true)
        } completionHandler: {
            LaunchDeckDiagnostics.log("showWindow animation completed")
        }
    }
}

final class LaunchDeckWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func close() {
        let targetFrame = frame.insetBy(dx: frame.width * 0.012, dy: frame.height * 0.012)
        LaunchDeckDiagnostics.log("window close requested")

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
            animator().setFrame(targetFrame, display: true)
        }, completionHandler: {
            Task { @MainActor in
                LaunchDeckDiagnostics.log("window close completed")
                super.close()
            }
        })
    }
}
