import AppKit
import SwiftUI

final class LaunchDeckShellWindowController: NSWindowController {
    private let displayTarget: LaunchDeckDisplayTarget
    private let openScale: CGFloat = 1.08
    private let openDuration: TimeInterval = 0.34
    private let closeDuration: TimeInterval = 0.28

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
        let finalFrame = displayTarget.resolve()?.frame ?? window.frame
        window.setFrame(finalFrame, display: true)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        guard let contentView = window.contentView else {
            window.alphaValue = 1
            return
        }
        prepareAnimationLayer(for: contentView)
        contentView.alphaValue = 0
        contentView.layer?.transform = CATransform3DMakeScale(openScale, openScale, 1)
        animateContentScale(
            for: contentView,
            from: openScale,
            to: 1,
            duration: openDuration,
            timingFunction: CAMediaTimingFunction(name: .easeOut),
            key: "launchdeck.window.open.scale"
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = openDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            contentView.animator().alphaValue = 1
        }
    }

    private func animateOut(window: NSWindow) {
        let contentView = window.contentView
        if let contentView {
            prepareAnimationLayer(for: contentView)
            contentView.alphaValue = 1
            animateContentScale(
                for: contentView,
                from: 1,
                to: openScale,
                duration: closeDuration,
                timingFunction: CAMediaTimingFunction(name: .easeIn),
                key: "launchdeck.window.close.scale"
            )
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = closeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            contentView?.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                window.orderOut(nil)
                window.alphaValue = 1
                contentView?.alphaValue = 1
                contentView?.layer?.removeAllAnimations()
                contentView?.layer?.transform = CATransform3DIdentity
            }
        })
    }

    private func prepareAnimationLayer(for contentView: NSView) {
        contentView.wantsLayer = true
        contentView.layoutSubtreeIfNeeded()
        guard let layer = contentView.layer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.transform = CATransform3DIdentity
        let frame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = frame
        CATransaction.commit()
    }

    private func animateContentScale(
        for contentView: NSView,
        from: CGFloat,
        to: CGFloat,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction,
        key: String
    ) {
        guard let layer = contentView.layer else { return }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = CATransform3DMakeScale(from, from, 1)
        animation.toValue = CATransform3DMakeScale(to, to, 1)
        animation.duration = duration
        animation.timingFunction = timingFunction
        layer.add(animation, forKey: key)
        layer.transform = CATransform3DMakeScale(to, to, 1)
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
