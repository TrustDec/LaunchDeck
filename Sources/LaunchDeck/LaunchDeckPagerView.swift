import AppKit
import SwiftUI

struct LaunchpadPagerView: NSViewRepresentable {
    let pages: [AnyView]
    let pageSignatures: [String]
    let currentPage: Int
    let isInteractionEnabled: Bool
    let interactionEngine: LaunchpadInteractionEngine
    let onPageChanged: (Int) -> Void

    func makeNSView(context: Context) -> LaunchpadPagerContainerView {
        let view = LaunchpadPagerContainerView()
        view.onPageChanged = onPageChanged
        view.update(
            pages: pages,
            pageSignatures: pageSignatures,
            currentPage: currentPage,
            isInteractionEnabled: isInteractionEnabled,
            interactionEngine: interactionEngine,
            animated: false
        )
        context.coordinator.hasMounted = true
        return view
    }

    func updateNSView(_ nsView: LaunchpadPagerContainerView, context: Context) {
        nsView.onPageChanged = onPageChanged
        let shouldAnimate = context.coordinator.hasMounted && pages.count == nsView.pageCount
        nsView.update(
            pages: pages,
            pageSignatures: pageSignatures,
            currentPage: currentPage,
            isInteractionEnabled: isInteractionEnabled,
            interactionEngine: interactionEngine,
            animated: shouldAnimate
        )
        context.coordinator.hasMounted = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var hasMounted = false
    }
}

@MainActor
final class LaunchpadPagerContainerView: NSView {
    private let clipView = NSClipView()
    private let documentView = NSView()
    private var hostingViews: [NSHostingView<AnyView>] = []
    private var currentPage = 0
    private var currentOffsetX: CGFloat = 0
    private var isInteractionEnabled = true
    private var isTracking = false
    private var scrollMonitor: Any?
    private var lastDeltaX: CGFloat = 0
    private var lastPanTranslationX: CGFloat = 0
    private var wheelAccumulator: CGFloat = 0
    private var lastWheelTurnTimestamp: TimeInterval = 0
    private var interactionEngine: LaunchpadInteractionEngine?
    private var pageSignatures: [String] = []

    var onPageChanged: ((Int) -> Void)?

    var pageCount: Int {
        hostingViews.count
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.masksToBounds = false

        clipView.drawsBackground = false
        clipView.postsBoundsChangedNotifications = false
        clipView.autoresizingMask = [.width, .height]
        addSubview(clipView)

        documentView.wantsLayer = true
        documentView.layer?.masksToBounds = false
        clipView.documentView = documentView

        let panGestureRecognizer = NSPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        addGestureRecognizer(panGestureRecognizer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        clipView.frame = bounds
        layoutPages()
        scrollToCurrentPage(animated: false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureEventMonitor()
    }

    func update(
        pages: [AnyView],
        pageSignatures: [String],
        currentPage: Int,
        isInteractionEnabled: Bool,
        interactionEngine: LaunchpadInteractionEngine,
        animated: Bool
    ) {
        if hostingViews.count != pages.count {
            rebuildPages(with: pages)
            self.pageSignatures = pageSignatures
        } else if self.pageSignatures != pageSignatures {
            for (index, page) in pages.enumerated() {
                hostingViews[index].rootView = page
            }
            self.pageSignatures = pageSignatures
        }

        self.isInteractionEnabled = isInteractionEnabled
        self.interactionEngine = interactionEngine
        let clampedPage = min(max(currentPage, 0), max(hostingViews.count - 1, 0))
        let pageChanged = clampedPage != self.currentPage
        self.currentPage = clampedPage

        if bounds.width > 0, bounds.height > 0 {
            layoutPages()
        } else {
            needsLayout = true
        }

        if !isTracking || pageChanged {
            scrollToCurrentPage(animated: animated)
        } else {
            interactionEngine.updatePageTracking(offsetX: clipView.bounds.origin.x, pageWidth: bounds.width)
        }
    }

    private func rebuildPages(with pages: [AnyView]) {
        hostingViews.forEach { $0.removeFromSuperview() }
        hostingViews = pages.map { page in
            let host = NSHostingView(rootView: page)
            host.translatesAutoresizingMaskIntoConstraints = true
            host.autoresizingMask = []
            host.wantsLayer = true
            host.layer?.masksToBounds = false
            documentView.addSubview(host)
            return host
        }
    }

    private func layoutPages() {
        let pageWidth = max(bounds.width, 1)
        let pageHeight = max(bounds.height, 1)
        documentView.frame = CGRect(
            x: 0,
            y: 0,
            width: pageWidth * CGFloat(max(hostingViews.count, 1)),
            height: pageHeight
        )

        for (index, host) in hostingViews.enumerated() {
            host.frame = CGRect(
                x: CGFloat(index) * pageWidth,
                y: 0,
                width: pageWidth,
                height: pageHeight
            )
        }

        updatePageTransforms()
    }

    private func scrollToCurrentPage(animated: Bool) {
        let targetX = bounds.width * CGFloat(currentPage)
        currentOffsetX = targetX
        let target = CGPoint(x: targetX, y: 0)
        interactionEngine?.endPageTracking(targetPage: currentPage)

        guard animated else {
            clipView.setBoundsOrigin(target)
            updatePageTransforms(for: targetX, animated: false)
            return
        }

        updatePageTransforms(for: targetX, animated: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.36
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.82, 0.22, 1)
            clipView.animator().setBoundsOrigin(target)
        } completionHandler: {
            Task { @MainActor in
                self.updatePageTransforms(for: targetX, animated: false)
            }
        }
    }

    private func configureEventMonitor() {
        if window == nil {
            detachEventMonitor()
            return
        }

        guard scrollMonitor == nil else {
            return
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else {
                return event
            }

            return self.handleScrollEvent(event)
        }
    }

    private func detachEventMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    private func handleScrollEvent(_ event: NSEvent) -> NSEvent? {
        guard isInteractionEnabled,
              event.window === window else {
            return event
        }

        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) || isTracking else {
            return event
        }

        let horizontal = event.scrollingDeltaX
        let vertical = event.scrollingDeltaY

        if event.hasPreciseScrollingDeltas {
            guard abs(horizontal) > abs(vertical), abs(horizontal) > 0.6 else {
                if isTracking, event.phase == .ended || event.momentumPhase == .ended {
                    finishInteractiveScroll()
                    return nil
                }

                return event
            }

            if !isTracking {
                beginInteractiveScroll()
            }

            let delta = -horizontal
            lastDeltaX = delta
            applyInteractiveScroll(delta: delta)

            if event.phase == .ended || event.momentumPhase == .ended {
                finishInteractiveScroll()
            }

            return nil
        }

        let dominantVertical = abs(vertical) >= abs(horizontal)
        if dominantVertical, abs(vertical) > 0.01 {
            return handleDiscreteWheelEvent(verticalDelta: vertical, timestamp: event.timestamp) ? nil : event
        }

        if abs(horizontal) > 0.01 {
            return handleDiscreteWheelEvent(verticalDelta: -horizontal, timestamp: event.timestamp) ? nil : event
        }

        return event
    }

    private func beginInteractiveScroll() {
        isTracking = true
        lastDeltaX = 0
        lastPanTranslationX = 0
        currentOffsetX = clipView.bounds.origin.x
        clipView.layer?.removeAllAnimations()
        interactionEngine?.beginPageTracking(currentPage: currentPage)
    }

    private func applyInteractiveScroll(delta: CGFloat) {
        let minOffset: CGFloat = 0
        let maxOffset = max(bounds.width * CGFloat(max(pageCount - 1, 0)), 0)
        var proposed = currentOffsetX + delta

        if proposed < minOffset {
            proposed = minOffset + (proposed - minOffset) * 0.22
        } else if proposed > maxOffset {
            proposed = maxOffset + (proposed - maxOffset) * 0.22
        }

        currentOffsetX = proposed
        clipView.setBoundsOrigin(CGPoint(x: proposed, y: 0))
        interactionEngine?.updatePageTracking(offsetX: proposed, pageWidth: bounds.width)
        updatePageTransforms(for: proposed, animated: false)
    }

    private func finishInteractiveScroll(projectedVelocity: CGFloat? = nil) {
        guard isTracking else {
            return
        }

        isTracking = false

        let pageWidth = max(bounds.width, 1)
        var target = Int(round(currentOffsetX / pageWidth))
        let projection = projectedVelocity.map { $0 * 0.18 } ?? (lastDeltaX * 6)

        if abs(projection) > 6 {
            target = Int(round((currentOffsetX + projection) / pageWidth))
        }

        target = min(max(target, 0), max(pageCount - 1, 0))
        currentPage = target
        onPageChanged?(target)
        scrollToCurrentPage(animated: true)
    }

    @objc
    private func handlePanGesture(_ recognizer: NSPanGestureRecognizer) {
        guard isInteractionEnabled else {
            return
        }

        switch recognizer.state {
        case .began:
            beginInteractiveScroll()
        case .changed:
            let translation = recognizer.translation(in: self)
            let delta = -(translation.x - lastPanTranslationX)
            lastPanTranslationX = translation.x
            applyInteractiveScroll(delta: delta)
        case .ended:
            let velocity = -recognizer.velocity(in: self).x
            finishInteractiveScroll(projectedVelocity: velocity)
        case .cancelled, .failed:
            finishInteractiveScroll(projectedVelocity: nil)
        default:
            break
        }
    }

    private func updatePageTransforms() {
        updatePageTransforms(for: currentOffsetX, animated: false)
    }

    private func updatePageTransforms(for offsetX: CGFloat, animated: Bool) {
        let pageWidth = max(bounds.width, 1)
        let timing = CAMediaTimingFunction(controlPoints: 0.18, 0.82, 0.22, 1)

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.36)
            CATransaction.setAnimationTimingFunction(timing)
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
        }

        for (index, host) in hostingViews.enumerated() {
            let pageOriginX = CGFloat(index) * pageWidth
            let signedDistance = (pageOriginX - offsetX) / pageWidth
            let distance = abs(signedDistance)
            let clamped = min(max(distance, 0), 1.4)
            let scale = 1 - min(clamped * 0.045, 0.045)
            let alpha = 1 - min(clamped * 0.18, 0.18)
            let lift = min(clamped * 18, 18)
            let shift = signedDistance * 24
            var transform = CATransform3DIdentity
            transform.m34 = -1 / 1200
            transform = CATransform3DTranslate(transform, shift, -lift, 0)
            transform = CATransform3DScale(transform, scale, scale, 1)

            host.layer?.transform = transform
            host.layer?.opacity = Float(alpha)
        }

        CATransaction.commit()
    }

    private func handleDiscreteWheelEvent(verticalDelta: CGFloat, timestamp: TimeInterval) -> Bool {
        wheelAccumulator += verticalDelta

        let threshold: CGFloat = 1.9
        guard abs(wheelAccumulator) >= threshold else {
            return false
        }

        guard timestamp - lastWheelTurnTimestamp > 0.18 else {
            wheelAccumulator = 0
            return true
        }

        let direction = wheelAccumulator > 0 ? -1 : 1
        let target = min(max(currentPage + direction, 0), max(pageCount - 1, 0))
        wheelAccumulator = 0
        lastWheelTurnTimestamp = timestamp

        guard target != currentPage else {
            return true
        }

        currentPage = target
        onPageChanged?(target)
        scrollToCurrentPage(animated: true)
        return true
    }
}
