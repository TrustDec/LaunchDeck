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

        guard let contentView = window.contentView else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        prepareAnimationLayer(for: contentView)
        setRasterization(for: contentView, enabled: true)
        window.alphaValue = 1
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        animateContentPresentation(
            for: contentView,
            fromScale: openScale,
            toScale: 1,
            fromOpacity: 0,
            toOpacity: 1,
            duration: openDuration,
            timingFunction: CAMediaTimingFunction(name: .easeOut),
            key: "launchdeck.window.open"
        ) { [weak contentView] in
            guard let contentView else { return }
            self.setRasterization(for: contentView, enabled: false)
        }
    }

    private func animateOut(window: NSWindow) {
        let contentView = window.contentView
        if let contentView {
            prepareAnimationLayer(for: contentView)
            animateContentPresentation(
                for: contentView,
                fromScale: 1,
                toScale: openScale,
                fromOpacity: 1,
                toOpacity: 0,
                duration: closeDuration,
                timingFunction: CAMediaTimingFunction(name: .easeIn),
                key: "launchdeck.window.close"
            ) {
                Task { @MainActor in
                    window.orderOut(nil)
                    contentView.layer?.removeAllAnimations()
                    contentView.layer?.transform = CATransform3DIdentity
                    contentView.layer?.opacity = 1
                    self.setRasterization(for: contentView, enabled: false)
                }
            }
            setRasterization(for: contentView, enabled: true)
            return
        }
        window.orderOut(nil)
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

    private func animateContentPresentation(
        for contentView: NSView,
        fromScale: CGFloat,
        toScale: CGFloat,
        fromOpacity: Float,
        toOpacity: Float,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction,
        key: String,
        completion: (() -> Void)? = nil
    ) {
        guard let layer = contentView.layer else { return }
        let scaleAnimation = CABasicAnimation(keyPath: "transform")
        scaleAnimation.fromValue = CATransform3DMakeScale(fromScale, fromScale, 1)
        scaleAnimation.toValue = CATransform3DMakeScale(toScale, toScale, 1)

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = fromOpacity
        opacityAnimation.toValue = toOpacity

        let group = CAAnimationGroup()
        group.animations = [scaleAnimation, opacityAnimation]
        group.duration = duration
        group.timingFunction = timingFunction
        group.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(completion)
        layer.transform = CATransform3DMakeScale(toScale, toScale, 1)
        layer.opacity = toOpacity
        layer.add(group, forKey: key)
        CATransaction.commit()
    }

    private func setRasterization(for contentView: NSView, enabled: Bool) {
        guard let layer = contentView.layer else { return }
        layer.shouldRasterize = enabled
        layer.rasterizationScale = contentView.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
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
