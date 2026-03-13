import CoreGraphics
import SwiftUI

@MainActor
final class LaunchpadInteractionEngine: ObservableObject {
    @Published private(set) var pagePosition: CGFloat = 0
    @Published private(set) var displayedFolder: LaunchItem?
    @Published private(set) var folderAnimationProgress: CGFloat = 0
    @Published private(set) var folderSourceFrame: CGRect = .zero

    private var isTrackingPages = false
    private var isClosingFolder = false
    private var pendingFolderCloseTask: Task<Void, Never>?
    private let pageEpsilon: CGFloat = 0.0005

    var isFolderVisible: Bool {
        displayedFolder != nil
    }

    func syncSettledPage(_ page: Int) {
        guard !isTrackingPages else {
            return
        }

        updatePagePosition(CGFloat(max(page, 0)))
    }

    func beginPageTracking(currentPage: Int) {
        isTrackingPages = true
        updatePagePosition(CGFloat(max(currentPage, 0)))
    }

    func updatePageTracking(offsetX: CGFloat, pageWidth: CGFloat) {
        guard pageWidth > 0 else {
            return
        }

        updatePagePosition(max(offsetX / pageWidth, 0))
    }

    func endPageTracking(targetPage: Int) {
        isTrackingPages = false
        updatePagePosition(CGFloat(max(targetPage, 0)))
    }

    func dotMetrics(for page: Int) -> (opacity: Double, scale: CGFloat, width: CGFloat) {
        let distance = abs(pagePosition - CGFloat(page))
        let focus = max(0, 1 - min(distance, 1))
        let opacity = 0.24 + Double(focus) * 0.76
        let scale = 0.82 + focus * 0.28
        let width = 8 + focus * 4
        return (opacity, scale, width)
    }

    func present(folder: LaunchItem, sourceFrame: CGRect?) {
        pendingFolderCloseTask?.cancel()
        pendingFolderCloseTask = nil
        isClosingFolder = false
        folderSourceFrame = sourceFrame ?? .zero
        displayedFolder = folder
        folderAnimationProgress = 0

        withAnimation(.spring(duration: 0.42, bounce: 0.12)) {
            folderAnimationProgress = 1
        }
    }

    func resetFolderPresentation() {
        guard !isClosingFolder else {
            return
        }

        displayedFolder = nil
        folderAnimationProgress = 0
        folderSourceFrame = .zero
    }

    func dismissFolder(afterClose: (() -> Void)? = nil) {
        guard displayedFolder != nil, !isClosingFolder else {
            return
        }

        pendingFolderCloseTask?.cancel()
        isClosingFolder = true

        withAnimation(.spring(duration: 0.28, bounce: 0.02)) {
            folderAnimationProgress = 0
        }

        pendingFolderCloseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(190))
            guard let self else {
                return
            }

            self.displayedFolder = nil
            self.folderSourceFrame = .zero
            self.isClosingFolder = false
            afterClose?()
        }
    }

    private func updatePagePosition(_ newValue: CGFloat) {
        guard abs(pagePosition - newValue) > pageEpsilon else {
            return
        }

        pagePosition = newValue
    }
}
