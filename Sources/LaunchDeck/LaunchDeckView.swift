import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct LaunchDeckView: View {
    @ObservedObject var store: LaunchDeckStore
    @StateObject private var interactionEngine = LaunchpadInteractionEngine()
    @State private var layout = LaunchpadLayout.default
    @State private var sceneOpacity = 0.0
    @State private var sceneScale = 0.985
    @State private var shouldMountPager = false
    @State private var shouldLoadCatalog = false
    @State private var shouldLoadBackdrop = false
    @State private var shouldLoadIcons = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background(shouldLoadWallpaper: shouldLoadBackdrop)
                Color.black.opacity(0.34).ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                        .padding(.top, layout.topInset)

                    Spacer(minLength: layout.topSpacing)

                    if shouldMountPager {
                        pageCarousel
                    } else {
                        launchSurfacePlaceholder
                    }

                    Spacer(minLength: layout.bottomSpacing)

                    footer
                        .padding(.bottom, layout.bottomInset)
                }
                .padding(.horizontal, layout.horizontalInset)
                .scaleEffect(interactionEngine.isFolderVisible ? 0.986 : 1)
                .blur(radius: interactionEngine.isFolderVisible ? 1.8 : 0)
                .saturation(interactionEngine.isFolderVisible ? 0.96 : 1)

                if store.isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }

                if let folder = interactionEngine.displayedFolder {
                    folderOverlay(for: folder, rootFrame: proxy.frame(in: .global))
                }
            }
            .opacity(sceneOpacity)
            .scaleEffect(sceneScale)
            .task(id: shouldLoadCatalog) {
                guard shouldLoadCatalog else {
                    return
                }

                await store.loadIfNeeded()
            }
            .task(id: proxy.size) {
                let updatedLayout = LaunchpadLayout(for: proxy.size)
                layout = updatedLayout
                store.updatePageCapacity(updatedLayout.pageCapacity)
            }
            .onAppear {
                LaunchDeckDiagnostics.log("view appeared")
                interactionEngine.syncSettledPage(store.currentPage)
                withAnimation(.spring(duration: 0.46, bounce: 0.12)) {
                    sceneOpacity = 1
                    sceneScale = 1
                }

                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    shouldMountPager = !LaunchDeckDiagnostics.disablePager
                    shouldLoadCatalog = !LaunchDeckDiagnostics.disableCatalog
                    LaunchDeckDiagnostics.log("mounted pager=\(shouldMountPager) loadCatalog=\(shouldLoadCatalog)")

                    try? await Task.sleep(for: .milliseconds(180))
                    shouldLoadIcons = true
                    LaunchDeckDiagnostics.log("load icons=\(shouldLoadIcons)")

                    try? await Task.sleep(for: .milliseconds(320))
                    shouldLoadBackdrop = !LaunchDeckDiagnostics.disableBackdrop
                    LaunchDeckDiagnostics.log("load backdrop=\(shouldLoadBackdrop)")
                }
            }
            .onChange(of: store.selectedFolder) { _, folder in
                handleFolderSelectionChange(folder)
            }
            .onChange(of: store.currentPage) { _, page in
                interactionEngine.syncSettledPage(page)
            }
            .onMoveCommand(perform: handleMoveCommand)
            .onExitCommand {
                if interactionEngine.isFolderVisible {
                    requestCloseFolder()
                } else {
                    NSApp.keyWindow?.close()
                }
            }
            .animation(.spring(duration: 0.44, bounce: 0.16), value: store.currentPage)
            .animation(.easeInOut(duration: 0.2), value: store.query)
            .animation(.spring(duration: 0.28, bounce: 0.08), value: interactionEngine.displayedFolder?.id)
        }
    }

    private var topBar: some View {
        ZStack(alignment: .trailing) {
            searchBar

            HStack(spacing: 10) {
                if store.isEditing {
                    Button("Done") {
                        store.exitEditMode()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.12), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                }

                Button {
                    NSApp.keyWindow?.close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.12), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func background(shouldLoadWallpaper: Bool) -> some View {
        DesktopBackdropView(shouldLoadWallpaper: shouldLoadWallpaper)
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        .clear,
                        Color.black.opacity(0.22),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .ignoresSafeArea()
    }

    private var launchSurfacePlaceholder: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
            .frame(width: layout.contentWidth, height: layout.contentHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchBar: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))

                TextField("Search", text: $store.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: layout.searchFontSize, weight: .medium))
                    .foregroundStyle(.white)

                if !store.query.isEmpty {
                    Button {
                        store.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(width: layout.searchWidth)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.13), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var pageCarousel: some View {
        let pagedItems = store.pagedItems
        let visiblePageRange = max(store.currentPage - 1, 0)...min(store.currentPage + 1, max(pagedItems.count - 1, 0))
        if LaunchDeckDiagnostics.useAppKitPager {
            return AnyView(
                LaunchpadPagerView(
                    pages: pagedItems.enumerated().map { index, items in
                        AnyView(
                            Group {
                                if visiblePageRange.contains(index) {
                                    pageContent(for: items, shouldLoadIcons: shouldLoadIcons)
                                } else {
                                    Color.clear
                                }
                            }
                        )
                    },
                    pageSignatures: pagedItems.enumerated().map { index, items in
                        let visibilityMarker = visiblePageRange.contains(index) ? "active" : "parked"
                        return "\(visibilityMarker)::" + items.map { $0.id.uuidString }.joined(separator: "|")
                    },
                    currentPage: store.currentPage,
                    isInteractionEnabled: !interactionEngine.isFolderVisible,
                    interactionEngine: interactionEngine,
                    onPageChanged: { page in
                        store.selectPage(page)
                    }
                )
            )
        }

        return AnyView(
            LaunchpadFallbackPagerView(
                currentPage: store.currentPage,
                pages: pagedItems.enumerated().map { index, items in
                    AnyView(
                        pageContent(
                            for: items,
                            shouldLoadIcons: shouldLoadIcons && visiblePageRange.contains(index)
                        )
                    )
                },
                onPageDelta: { delta in
                    guard !interactionEngine.isFolderVisible else {
                        return
                    }

                    if delta > 0 {
                        store.nextPage()
                    } else if delta < 0 {
                        store.previousPage()
                    }
                }
            )
        )
    }

    @ViewBuilder
    private func pageContent(for items: [LaunchItem], shouldLoadIcons: Bool) -> some View {
        LaunchpadPageView(
            items: items,
            layout: layout,
            shouldLoadIcons: shouldLoadIcons,
            isEditing: store.isEditing,
            isFiltering: !store.canEditLayout,
            beginDragging: { item in
                store.beginDragging(item)
            },
            dropOnItem: { item in
                store.dropDraggedItem(on: item.id)
            },
            enterEditMode: {
                store.enterEditMode()
            },
            completeDragging: {
                store.completeDragging()
            }
        ) { item, sourceFrame in
            openItem(item, sourceFrame: sourceFrame)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let lastError = store.lastError {
                Text(lastError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.82))
            } else if store.isEditing {
                Text("Drag to reorder. Drop on an app to create a folder.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }

            HStack(spacing: 10) {
                ForEach(0..<store.pageCount, id: \.self) { page in
                    let metrics = interactionEngine.dotMetrics(for: page)
                    Button {
                        withAnimation(.spring(duration: 0.38, bounce: 0.12)) {
                            store.selectPage(page)
                        }
                    } label: {
                        Circle()
                            .fill(.white.opacity(metrics.opacity))
                            .frame(
                                width: metrics.width,
                                height: metrics.width
                            )
                            .scaleEffect(metrics.scale)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func folderOverlay(for folder: LaunchItem, rootFrame: CGRect) -> some View {
        let sourceRect = convertedFolderSourceFrame(in: rootFrame)
        let targetRect = targetFolderFrame(in: rootFrame)
        let progress = interactionEngine.folderAnimationProgress
        let animatedFrame = interpolatedRect(from: sourceRect, to: targetRect, progress: progress)
        let contentOpacity = max(0, min((progress - 0.24) / 0.76, 1))
        let backgroundOpacity = 0.2 * progress

        return ZStack {
            Color.black.opacity(backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    requestCloseFolder()
                }

            VStack(spacing: max(layout.folderSpacing - 4, 18)) {
                if !folder.title.isEmpty {
                    Text(folder.title)
                        .font(.system(size: layout.folderTitleSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.94))
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(layout.folderItemWidth), spacing: layout.folderSpacing), count: layout.folderColumns),
                    spacing: layout.folderSpacing
                ) {
                    ForEach(folder.children) { child in
                        FolderItemButton(item: child, shouldLoadIcons: shouldLoadIcons) {
                            requestCloseFolder {
                                store.activate(child)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Button {
                    requestCloseFolder()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .opacity(contentOpacity)
            .padding(.horizontal, layout.folderHorizontalPadding)
            .padding(.vertical, layout.folderVerticalPadding)
            .frame(width: animatedFrame.width)
            .frame(height: animatedFrame.height)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.black.opacity(0.3))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 22, y: 14)
            .opacity(max(progress, 0.001))
            .scaleEffect(0.92 + progress * 0.08)
            .position(x: animatedFrame.midX, y: animatedFrame.midY)
        }
    }

    private func handleFolderSelectionChange(_ folder: LaunchItem?) {
        guard let folder else {
            interactionEngine.resetFolderPresentation()
            return
        }

        if interactionEngine.displayedFolder?.id == folder.id {
            return
        }

        interactionEngine.present(folder: folder, sourceFrame: interactionEngine.folderSourceFrame)
    }

    private func requestCloseFolder(afterClose: (() -> Void)? = nil) {
        interactionEngine.dismissFolder {
            store.closeFolder()
            afterClose?()
        }
    }

    private func convertedFolderSourceFrame(in rootFrame: CGRect) -> CGRect {
        guard interactionEngine.folderSourceFrame != .zero else {
            let fallback = CGRect(
                x: rootFrame.midX - 46,
                y: rootFrame.midY - 46,
                width: 92,
                height: 92
            )
            return fallback
        }

        return CGRect(
            x: interactionEngine.folderSourceFrame.minX - rootFrame.minX,
            y: interactionEngine.folderSourceFrame.minY - rootFrame.minY,
            width: interactionEngine.folderSourceFrame.width,
            height: interactionEngine.folderSourceFrame.height
        )
    }

    private func targetFolderFrame(in rootFrame: CGRect) -> CGRect {
        CGRect(
            x: rootFrame.width * 0.5 - layout.folderWidth * 0.5,
            y: rootFrame.height * 0.5 - layout.folderMinHeight * 0.5,
            width: layout.folderWidth,
            height: layout.folderMinHeight
        )
    }

    private func interpolatedRect(from source: CGRect, to target: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: source.minX + (target.minX - source.minX) * progress,
            y: source.minY + (target.minY - source.minY) * progress,
            width: source.width + (target.width - source.width) * progress,
            height: source.height + (target.height - source.height) * progress
        )
    }

    private func openItem(_ item: LaunchItem, sourceFrame: CGRect?) {
        if item.isFolder {
            interactionEngine.present(folder: item, sourceFrame: sourceFrame)
        }

        store.activate(item)
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard !interactionEngine.isFolderVisible else {
            return
        }

        switch direction {
        case .left:
            withAnimation(.spring(duration: 0.38, bounce: 0.12)) {
                store.previousPage()
            }
        case .right:
            withAnimation(.spring(duration: 0.38, bounce: 0.12)) {
                store.nextPage()
            }
        default:
            break
        }
    }
}

private struct LaunchpadLayout: Equatable {
    let columns: Int
    let rows: Int
    let iconWidth: CGFloat
    let iconHeight: CGFloat
    let iconLabelWidth: CGFloat
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let horizontalInset: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let topSpacing: CGFloat
    let bottomSpacing: CGFloat
    let searchWidth: CGFloat
    let searchFontSize: CGFloat
    let folderWidth: CGFloat
    let folderMinHeight: CGFloat
    let folderTitleSize: CGFloat
    let folderColumns: Int
    let folderSpacing: CGFloat
    let folderItemWidth: CGFloat
    let folderHorizontalPadding: CGFloat
    let folderVerticalPadding: CGFloat

    var pageCapacity: Int {
        columns * rows
    }

    static let `default` = LaunchpadLayout(for: CGSize(width: 1440, height: 900))

    init(for size: CGSize) {
        let width = max(size.width, 980)
        let height = max(size.height, 700)

        horizontalInset = Self.snap(max(32, min(width * 0.06, 88)))
        topInset = Self.snap(max(26, min(height * 0.042, 46)))
        bottomInset = Self.snap(max(20, min(height * 0.03, 34)))
        topSpacing = Self.snap(max(18, min(height * 0.03, 28)))
        bottomSpacing = Self.snap(max(12, min(height * 0.022, 20)))

        searchWidth = Self.snap(min(max(width * 0.22, 300), 430))
        searchFontSize = Self.snap(width < 1180 ? 16 : 18)

        let availableWidth = width - horizontalInset * 2
        let availableHeight = height - topInset - bottomInset - 108

        columns = min(max(Int((availableWidth + 18) / 128), 5), 9)
        rows = min(max(Int((availableHeight + 16) / 150), 4), 6)

        let rawHorizontalSpacing = (availableWidth - CGFloat(columns) * 104) / CGFloat(max(columns - 1, 1))
        horizontalSpacing = Self.snap(min(max(rawHorizontalSpacing, 18), 40))

        let rawVerticalSpacing = (availableHeight - CGFloat(rows) * 114) / CGFloat(max(rows - 1, 1))
        verticalSpacing = Self.snap(min(max(rawVerticalSpacing, 18), 36))

        contentWidth = Self.snap(CGFloat(columns) * 104 + CGFloat(max(columns - 1, 0)) * horizontalSpacing)
        contentHeight = Self.snap(CGFloat(rows) * 114 + CGFloat(max(rows - 1, 0)) * verticalSpacing)

        iconWidth = 104
        iconHeight = 114
        iconLabelWidth = 104

        folderColumns = width < 1180 ? 3 : 4
        folderTitleSize = Self.snap(width < 1180 ? 24 : 28)
        folderSpacing = Self.snap(width < 1180 ? 22 : 26)
        folderItemWidth = Self.snap(width < 1180 ? 90 : 98)
        folderHorizontalPadding = Self.snap(width < 1180 ? 42 : 52)
        folderVerticalPadding = Self.snap(width < 1180 ? 28 : 34)
        folderWidth = Self.snap(min(max(width * 0.36, 420), 640))
        folderMinHeight = Self.snap(min(max(height * 0.34, 300), 500))
    }

    private static func snap(_ value: CGFloat) -> CGFloat {
        value.rounded(.toNearestOrAwayFromZero)
    }
}

private struct DesktopBackdropView: View {
    let shouldLoadWallpaper: Bool
    @State private var wallpaper: NSImage?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.2, blue: 0.28),
                    Color(red: 0.09, green: 0.11, blue: 0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let wallpaper {
                Image(nsImage: wallpaper)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 18)
                    .saturation(1.08)
                    .overlay(Color.black.opacity(0.14))
                    .transition(.opacity)
            } else {
                RadialGradient(
                    colors: [
                        Color(red: 0.32, green: 0.5, blue: 0.82).opacity(0.45),
                        Color.clear,
                    ],
                    center: .topLeading,
                    startRadius: 40,
                    endRadius: 520
                )
            }
        }
        .ignoresSafeArea()
        .task(id: shouldLoadWallpaper) {
            guard shouldLoadWallpaper else {
                return
            }

            LaunchDeckDiagnostics.log("begin wallpaper load")
            wallpaper = await DesktopWallpaperLoader.loadAsync()
            LaunchDeckDiagnostics.log("finish wallpaper load success=\(wallpaper != nil)")
        }
    }
}

private enum DesktopWallpaperLoader {
    static func loadAsync() async -> NSImage? {
        await Task.detached(priority: .utility) {
            load()
        }.value
    }

    static func load() -> NSImage? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            return nil
        }

        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]),
              values.isDirectory != true else {
            LaunchDeckDiagnostics.log("skip wallpaper path because it is not a regular image file: \(url.path)")
            return nil
        }

        let pixelScale = max(screen.backingScaleFactor, 1)
        let maxDimension = max(screen.frame.width, screen.frame.height) * pixelScale
        return downsampledImage(at: url, maxPixelSize: min(maxDimension, 2560))
    }

    private static func downsampledImage(at url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }

        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(maxPixelSize, 1024)),
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return NSImage(contentsOf: url)
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

private struct LaunchpadPageView: View {
    let items: [LaunchItem]
    let layout: LaunchpadLayout
    let shouldLoadIcons: Bool
    let isEditing: Bool
    let isFiltering: Bool
    let beginDragging: (LaunchItem) -> Void
    let dropOnItem: (LaunchItem) -> Bool
    let enterEditMode: () -> Void
    let completeDragging: () -> Void
    let action: (LaunchItem, CGRect?) -> Void

    var body: some View {
        ZStack {
            if items.isEmpty {
                Text("No Results")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                LazyVGrid(columns: gridColumns, alignment: .center, spacing: layout.verticalSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        LaunchpadItemButton(
                            item: item,
                            layout: layout,
                            loadIndex: index,
                            shouldLoadIcons: shouldLoadIcons,
                            isEditing: isEditing,
                            isFiltering: isFiltering,
                            beginDragging: {
                                beginDragging(item)
                            },
                            completeDragging: completeDragging,
                            dropOnItem: {
                                dropOnItem(item)
                            },
                            enterEditMode: enterEditMode
                        ) { sourceFrame in
                            action(item, sourceFrame)
                        }
                    }
                }
                .frame(width: layout.contentWidth, height: layout.contentHeight)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(layout.iconWidth), spacing: layout.horizontalSpacing, alignment: .top),
            count: layout.columns
        )
    }
}

private struct LaunchpadFallbackPagerView: View {
    let currentPage: Int
    let pages: [AnyView]
    let onPageDelta: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        page
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .opacity(index == currentPage ? 1 : 0.94)
                            .scaleEffect(index == currentPage ? 1 : 0.985)
                            .allowsHitTesting(index == currentPage)
                    }
                }
                .frame(width: proxy.size.width * CGFloat(max(pages.count, 1)), alignment: .leading)
                .offset(x: -CGFloat(currentPage) * proxy.size.width)
                .animation(.spring(duration: 0.34, bounce: 0.1), value: currentPage)
                .clipped()

                FallbackPagerInputMonitor(onPageDelta: onPageDelta)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(true)
            }
            .onAppear {
                LaunchDeckDiagnostics.log("fallback pager appeared currentPage=\(currentPage) pageCount=\(pages.count)")
            }
        }
    }
}

private struct FallbackPagerInputMonitor: NSViewRepresentable {
    let onPageDelta: (Int) -> Void

    func makeNSView(context: Context) -> FallbackPagerInputView {
        let view = FallbackPagerInputView()
        view.onPageDelta = onPageDelta
        return view
    }

    func updateNSView(_ nsView: FallbackPagerInputView, context: Context) {
        nsView.onPageDelta = onPageDelta
    }
}

@MainActor
final class FallbackPagerInputView: NSView {
    var onPageDelta: ((Int) -> Void)?

    private var scrollMonitor: Any?
    private var wheelAccumulator: CGFloat = 0
    private var lastTurnTimestamp: TimeInterval = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            detachMonitor()
        } else {
            attachMonitorIfNeeded()
        }
    }

    private func attachMonitorIfNeeded() {
        guard scrollMonitor == nil else {
            return
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else {
                return event
            }

            return self.handleScroll(event)
        }
    }

    private func detachMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else {
            return event
        }

        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else {
            return event
        }

        let dominantVertical = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
        let delta = dominantVertical ? event.scrollingDeltaY : -event.scrollingDeltaX
        guard abs(delta) > 0.01 else {
            return event
        }

        wheelAccumulator += delta
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 18 : 1.8
        guard abs(wheelAccumulator) >= threshold else {
            return nil
        }

        guard event.timestamp - lastTurnTimestamp > 0.18 else {
            wheelAccumulator = 0
            return nil
        }

        let direction = wheelAccumulator > 0 ? -1 : 1
        wheelAccumulator = 0
        lastTurnTimestamp = event.timestamp
        onPageDelta?(direction)
        return nil
    }
}

private struct LaunchpadItemButton: View {
    let item: LaunchItem
    let layout: LaunchpadLayout
    let loadIndex: Int
    let shouldLoadIcons: Bool
    let isEditing: Bool
    let isFiltering: Bool
    let beginDragging: () -> Void
    let completeDragging: () -> Void
    let dropOnItem: () -> Bool
    let enterEditMode: () -> Void
    let action: (CGRect?) -> Void

    @State private var isHovering = false
    @State private var isDropTargeted = false
    @State private var jiggle = false

    var body: some View {
        Button {
            guard !isEditing else {
                return
            }

            action(nil)
        } label: {
            VStack(spacing: 10) {
                TileIconView(
                    item: item,
                    iconSize: iconSize,
                    folderIconSize: folderIconSize,
                    miniIconSize: miniIconSize,
                    loadIndex: loadIndex,
                    shouldLoadIcons: shouldLoadIcons
                )
                    .scaleEffect(isHovering ? 1.06 : 1)

                Text(item.title)
                    .font(.system(size: layout.iconLabelWidth < 100 ? 12 : 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.34), radius: 6, y: 3)
                    .frame(width: layout.iconLabelWidth)
            }
            .frame(width: layout.iconWidth, height: layout.iconHeight, alignment: .top)
            .contentShape(Rectangle())
            .scaleEffect(isDropTargeted ? 1.06 : (isHovering ? 1.03 : 1))
            .rotationEffect(.degrees(isEditing ? (jiggle ? 1.25 : -1.25) : 0))
            .offset(x: isEditing ? (jiggle ? 0.9 : -0.9) : 0)
            .overlay(alignment: .topTrailing) {
                if isEditing {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .padding(.trailing, 8)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    guard !isFiltering else {
                        return
                    }

                    enterEditMode()
                }
        )
        .onChange(of: isEditing) { _, editing in
            updateJiggle(editing)
        }
        .onAppear {
            updateJiggle(isEditing)
        }
        .onDrag {
            guard !isFiltering else {
                return NSItemProvider()
            }

            beginDragging()
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], isTargeted: $isDropTargeted) { _ in
            let accepted = dropOnItem()
            completeDragging()
            return accepted
        }
        .contextMenu {
            if !isEditing && !isFiltering {
                Button("Edit Layout") {
                    enterEditMode()
                }
            }
        }
    }

    private var iconSize: CGFloat {
        max(layout.iconWidth - 32, 64)
    }

    private var folderIconSize: CGFloat {
        max(iconSize + 6, 74)
    }

    private var miniIconSize: CGFloat {
        folderIconSize >= 78 ? 24 : 22
    }

    private func updateJiggle(_ editing: Bool) {
        guard editing else {
            jiggle = false
            return
        }

        let duration = 0.14 + Double(abs(item.title.hashValue % 5)) * 0.015
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
            jiggle = true
        }
    }
}

private struct FolderItemButton: View {
    let item: LaunchItem
    let shouldLoadIcons: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                TileIconView(item: item, iconSize: 70, folderIconSize: 78, miniIconSize: 24, loadIndex: 0, shouldLoadIcons: shouldLoadIcons)

                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 98)
            }
            .frame(width: 98, height: 114, alignment: .top)
        }
        .buttonStyle(.plain)
    }
}

private struct TileIconView: View {
    let item: LaunchItem
    let iconSize: CGFloat
    let folderIconSize: CGFloat
    let miniIconSize: CGFloat
    let loadIndex: Int
    let shouldLoadIcons: Bool
    @State private var icon: NSImage?

    var body: some View {
        ZStack {
            if item.isFolder {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .frame(width: folderIconSize, height: folderIconSize)

                FolderPreviewView(children: Array(item.children.prefix(4)), miniIconSize: miniIconSize, shouldLoadIcons: false)
            } else if let icon {
                AppIconImageView(image: icon)
                    .frame(width: iconSize, height: iconSize)
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: iconSize, height: iconSize)

                Image(systemName: "app.fill")
                    .font(.system(size: iconSize * 0.42, weight: .medium))
                    .foregroundStyle(.white.opacity(0.74))
            }
        }
        .frame(width: max(folderIconSize, iconSize), height: max(folderIconSize, iconSize))
        .task(id: "\(item.id.uuidString)-\(shouldLoadIcons)") {
            guard shouldLoadIcons, !item.isFolder, let bundleURL = item.bundleURL else {
                return
            }

            let clampedIndex = min(loadIndex, 20)
            if clampedIndex > 0 {
                try? await Task.sleep(for: .milliseconds(35 * clampedIndex))
            }

            icon = AppIconResolver.icon(for: bundleURL)
        }
    }
}

private struct FolderPreviewView: View {
    let children: [LaunchItem]
    let miniIconSize: CGFloat
    let shouldLoadIcons: Bool

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(miniIconSize), spacing: 4), count: 2), spacing: 4) {
            ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                MiniAppIconView(bundleURL: child.bundleURL, size: miniIconSize, shouldLoadIcons: shouldLoadIcons)
            }
        }
    }
}

private struct MiniAppIconView: View {
    let bundleURL: URL?
    let size: CGFloat
    let shouldLoadIcons: Bool
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                AppIconImageView(image: icon)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: "\(bundleURL?.path() ?? "nil")-\(shouldLoadIcons)") {
            guard shouldLoadIcons, let bundleURL else {
                return
            }

            icon = AppIconResolver.icon(for: bundleURL, preferredSize: 32)
        }
    }
}

private struct AppIconImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageFrameStyle = .none
        view.animates = false
        view.canDrawSubviewsIntoLayer = true
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = image
    }
}

@MainActor
private enum AppIconResolver {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    static func icon(for bundleURL: URL, preferredSize: CGFloat = 128) -> NSImage {
        let resolvedURL = canonicalizedURL(for: bundleURL)
        let key = resolvedURL.path as NSString
        if let cached = cache.object(forKey: key) {
            LaunchDeckDiagnostics.logIconLoad(path: resolvedURL.path, duration: 0, cacheHit: true)
            return cached
        }

        let start = Date()
        let image: NSImage = autoreleasepool {
            let effective = effectiveIcon(for: resolvedURL)
            if let effective, shouldUseSystemFileIcon(effective) {
                return effective
            }

            if let bundleIcon = bundleIcon(for: resolvedURL) {
                return bundleIcon
            }

            return workspaceIcon(for: resolvedURL)
        }

        cache.setObject(image, forKey: key)
        LaunchDeckDiagnostics.logIconLoad(path: resolvedURL.path, duration: Date().timeIntervalSince(start), cacheHit: false)
        return image
    }

    private static func workspaceIcon(for bundleURL: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: bundleURL.path())
    }

    private static func effectiveIcon(for bundleURL: URL) -> NSImage? {
        let values = try? bundleURL.resourceValues(forKeys: [.effectiveIconKey])
        return values?.effectiveIcon as? NSImage
    }

    private static func canonicalizedURL(for bundleURL: URL) -> URL {
        if let values = try? bundleURL.resourceValues(forKeys: [.canonicalPathKey]),
           let canonicalPath = values.canonicalPath {
            return URL(fileURLWithPath: canonicalPath)
        }

        return bundleURL.standardizedFileURL
    }

    private static func shouldUseSystemFileIcon(_ image: NSImage) -> Bool {
        let description = String(describing: image)

        if description.contains("ISBundleIcon") {
            return true
        }

        return !description.contains("ISGenericDocumentIcon")
            && !description.contains("Type: com.apple.application-bundle")
            && !description.contains("Type: com.apple.bundle")
    }

    private static func bundleIcon(for bundleURL: URL) -> NSImage? {
        guard let bundle = Bundle(url: bundleURL),
              let resourceURL = bundle.resourceURL else {
            return nil
        }

        for candidate in iconNameCandidates(from: bundle) {
            let normalized = candidate.hasSuffix(".icns") ? candidate : "\(candidate).icns"
            let iconURL = resourceURL.appending(path: normalized)
            if let image = NSImage(contentsOf: iconURL) {
                return image
            }

            let baseName = candidate.replacingOccurrences(of: ".icns", with: "")
            if let image = bundle.image(forResource: NSImage.Name(baseName)) {
                return image
            }
        }

        return nil
    }

    private static func iconNameCandidates(from bundle: Bundle) -> [String] {
        var candidates: [String] = []

        if let iconFile = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
            candidates.append(iconFile)
        }

        if let iconName = bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String {
            candidates.append(iconName)
        }

        if let icons = bundle.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            candidates.append(contentsOf: files)
        }

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}
