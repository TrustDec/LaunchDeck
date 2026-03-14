import AppKit
import ImageIO
import SwiftUI

struct LaunchDeckShellView: View {
    @ObservedObject var store: LaunchDeckShellStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var pageColumns = 6
    @State private var pageRows = 5
    @State private var wallpaper: NSImage?

    private var metrics: ShellLayoutMetrics {
        store.compactMode ? .compact : .regular
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundAtmosphere

                VStack(spacing: 28) {
                    topBar
                        .padding(.top, 30)

                    if store.isSearching {
                        searchResultsGrid(in: proxy.size)
                    } else {
                        pageGrid(in: proxy.size)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 36)

                SearchCommandMonitor(
                    isEnabled: store.isSearching,
                    onRevealSelectedResult: {
                        store.revealSelectedSearchResultInFinder()
                    }
                )
                .allowsHitTesting(false)
            }
            .task {
                await store.loadIfNeeded()
            }
            .onChange(of: store.query) { _, _ in
                store.syncSearchSelection()
            }
            .task(id: "\(Int(proxy.size.width))x\(Int(proxy.size.height))-\(store.compactMode)") {
                let minColumns = store.compactMode ? 6 : 7
                let maxColumns = store.compactMode ? 11 : 10
                let minRows = store.compactMode ? 4 : 5
                let maxRows = store.compactMode ? 7 : 6
                let columns = max(min(Int((proxy.size.width - 120) / metrics.horizontalFootprint), maxColumns), minColumns)
                let rows = max(min(Int((proxy.size.height - 240) / metrics.verticalFootprint), maxRows), minRows)
                pageColumns = columns
                pageRows = rows
                store.updatePageCapacity(columns * rows)
            }
            .onMoveCommand { direction in
                if store.isSearching {
                    switch direction {
                    case .up:
                        store.selectPreviousSearchResult()
                    case .down:
                        store.selectNextSearchResult()
                    default:
                        break
                    }
                } else {
                    guard store.selectedFolder == nil else { return }
                    switch direction {
                    case .left:
                        store.previousPage()
                    case .right:
                        store.nextPage()
                    default:
                        break
                    }
                }
            }
            .onExitCommand {
                store.handleExitCommand()
            }
            .sheet(item: $store.selectedFolder) { folder in
                folderSheet(for: folder)
            }
        }
    }

    private var backgroundAtmosphere: some View {
        ZStack {
            Color.black

            if let wallpaper {
                Image(nsImage: wallpaper)
                    .resizable()
                    .scaledToFill()
                    .saturation(1.04)
                    .blur(radius: 20)
                    .overlay(Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08))
            } else {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)]
                        : [Color(nsColor: .windowBackgroundColor), Color(nsColor: .controlBackgroundColor)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.02 : 0.05),
                    Color.clear,
                    Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .task(id: colorScheme == .dark) {
            wallpaper = await DesktopWallpaperLoader.loadAsync()
        }
    }

    private func searchResultsGrid(in size: CGSize) -> some View {
        let columns = Array(repeating: GridItem(.fixed(metrics.labelWidth), spacing: metrics.columnSpacing), count: max(pageColumns, 1))

        return ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: metrics.rowSpacing) {
                ForEach(store.filteredItems) { item in
                    Button {
                        store.activate(item)
                    } label: {
                        VStack(spacing: 10) {
                            ShellIconTile(
                                item: item,
                                isActive: item.id == store.selectedFolder?.id,
                                metrics: metrics
                            )

                            VStack(spacing: 3) {
                                SearchHighlightedTitle(
                                    title: item.title,
                                    query: store.query,
                                    width: metrics.labelWidth,
                                    fontSize: 13,
                                    fontWeight: .medium,
                                    foregroundColor: Color(nsColor: .labelColor),
                                    highlightColor: Color(nsColor: .controlAccentColor)
                                )

                                if let subtitle = searchResultSubtitle(for: item) {
                                    SearchHighlightedTitle(
                                        title: subtitle,
                                        query: store.query,
                                        width: metrics.labelWidth,
                                        fontSize: 11,
                                        fontWeight: .regular,
                                        foregroundColor: Color(nsColor: .secondaryLabelColor),
                                        highlightColor: Color(nsColor: .controlAccentColor).opacity(0.92)
                                    )
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(nsColor: .controlAccentColor).opacity(store.selectedSearchResultID == item.id ? (colorScheme == .dark ? 0.18 : 0.14) : 0))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(nsColor: .controlAccentColor).opacity(store.selectedSearchResultID == item.id ? 0.5 : 0), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onTapGesture {
                        store.selectedSearchResultID = item.id
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(size.height - 220, 240), alignment: .top)
        .padding(.horizontal, max((size.width - min(size.width - 40, 920)) / 2, 0))
        .padding(.vertical, 8)
        .background {
            SystemGlassSurface(cornerRadius: 30, style: .regular)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: 24, y: 14)
    }

    private func searchResultSubtitle(for item: LaunchItem) -> String? {
        if let subtitle = item.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !subtitle.isEmpty {
            return subtitle
        }

        guard let bundleURL = item.bundleURL else {
            return item.isFolder ? "Folder" : nil
        }

        let path = bundleURL.path
        if path.hasPrefix("/System/Applications") {
            return "System App"
        }
        if path.hasPrefix("/Applications") {
            return "Applications"
        }
        if path.hasPrefix(NSHomeDirectory()) {
            return "Home"
        }
        return bundleURL.deletingLastPathComponent().lastPathComponent
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))

                    TextField("Search apps", text: $store.query)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .onSubmit {
                            if let item = store.primarySearchResult {
                                store.activate(item)
                            }
                        }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background {
                    SystemGlassSurface(cornerRadius: 18, style: .regular)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    NSApp.keyWindow?.close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .frame(width: 36, height: 36)
                        .background {
                            SystemGlassSurface(cornerRadius: 18, style: .regular)
                        }
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if store.isSearching, let selectedItem = store.primarySearchResult {
                HStack(spacing: 10) {
                    Text(selectedItem.title)
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button {
                        store.activate(selectedItem)
                    } label: {
                        searchQuickActionLabel("Open", keyHint: "Return")
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.revealInFinder(selectedItem)
                    } label: {
                        searchQuickActionLabel("Reveal", keyHint: "⌘ Return")
                    }
                    .buttonStyle(.plain)

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
            }
        }
        .frame(maxWidth: 720)
    }

    private func searchQuickActionLabel(_ title: String, keyHint: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text(keyHint)
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            SystemGlassSurface(cornerRadius: 12, style: .clear)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func pageGrid(in size: CGSize) -> some View {
        let contentWidth = max(size.width - 72, 320)
        return NativePageControllerHost(pageCount: store.pageCount, selection: pageSelectionBinding) { page in
            let clampedPage = min(max(page, 0), max(store.pageCount - 1, 0))
            let pageItems = store.pagedItems[clampedPage]
            return AnyView(
                pageContent(items: pageItems)
                    .frame(width: contentWidth)
            )
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .frame(width: contentWidth, alignment: .center)
    }

    private var pageSelectionBinding: Binding<Int> {
        Binding(
            get: { min(max(store.currentPage, 0), max(store.pageCount - 1, 0)) },
            set: { store.selectPage($0) }
        )
    }

    private func pageContent(items: [LaunchItem]) -> some View {
        let rows = items.chunked(into: max(pageColumns, 1))
        let rowHeight = CGFloat(pageRows) * metrics.cellHeight + CGFloat(max(pageRows - 1, 0)) * metrics.rowSpacing

        return VStack(alignment: .center, spacing: metrics.rowSpacing - 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, rowItems in
                HStack(alignment: .top, spacing: metrics.columnSpacing) {
                    ForEach(Array(rowItems.enumerated()), id: \.element.id) { _, item in
                        Button {
                            store.activate(item)
                        } label: {
                            VStack(spacing: 10) {
                                ShellIconTile(
                                    item: item,
                                    isActive: item.id == store.selectedFolder?.id,
                                    metrics: metrics
                                )

                                Text(item.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color(nsColor: .labelColor))
                                    .lineLimit(1)
                                    .frame(width: metrics.labelWidth)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(rowItems.count..<pageColumns, id: \.self) { _ in
                        Color.clear
                            .frame(width: metrics.labelWidth, height: metrics.cellHeight)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: rowHeight, alignment: .top)
        .padding(.top, 8)
    }

    private func folderSheet(for folder: LaunchItem) -> some View {
        let resolvedFolder = store.items.first(where: { $0.id == folder.id && $0.isFolder }) ?? folder
        let itemCount = max(resolvedFolder.children.count, 1)
        let columns = min(max(Int(ceil(sqrt(Double(itemCount)))), 1), 5)
        let tileSize = metrics.folderTileSize
        let gridColumns = Array(repeating: GridItem(.fixed(tileSize), spacing: 22), count: columns)

        return VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(resolvedFolder.title)
                    .font(.system(size: 28, weight: .semibold))
                Spacer(minLength: 16)
                Button("Done") {
                    store.closeFolder()
                }
                .keyboardShortcut(.cancelAction)
            }

            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: gridColumns, spacing: 24) {
                    ForEach(resolvedFolder.children) { child in
                        Button {
                            store.closeFolder()
                            store.activate(child)
                        } label: {
                            VStack(spacing: 10) {
                                ShellIconTile(item: child, isActive: false, metrics: metrics)
                                Text(child.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color(nsColor: .labelColor))
                                    .lineLimit(1)
                                    .frame(width: tileSize)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(28)
        .frame(minWidth: 640, minHeight: 460, alignment: .topLeading)
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

private struct ShellIconTile: View {
    let item: LaunchItem
    let isActive: Bool
    let metrics: ShellLayoutMetrics
    @State private var icon: NSImage?

    var body: some View {
        ZStack {
            if item.isFolder {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.clear)
                    .background {
                        SystemGlassSurface(cornerRadius: 22, style: .regular)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 4), count: 2), spacing: 4) {
                    ForEach(Array(item.children.prefix(4).enumerated()), id: \.offset) { _, child in
                        MiniShellIcon(bundleURL: child.bundleURL)
                    }
                }
                .padding(10)
            } else if let icon {
                AppIconImageView(image: icon)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35))

                Image(systemName: "app.fill")
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
        }
        .frame(width: metrics.iconFrame, height: metrics.iconFrame)
        .overlay {
            RoundedRectangle(cornerRadius: item.isFolder ? metrics.folderCornerRadius : metrics.iconCornerRadius, style: .continuous)
                .stroke(Color(nsColor: .controlAccentColor).opacity(isActive ? 0.7 : 0), lineWidth: 1.5)
        }
        .task(id: item.id) {
            guard !item.isFolder, let bundleURL = item.bundleURL else { return }
            icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
        }
    }
}

private struct MiniShellIcon: View {
    let bundleURL: URL?
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                AppIconImageView(image: icon)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: bundleURL?.path()) {
            guard let bundleURL else { return }
            icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
        }
    }
}

private struct SearchHighlightedTitle: View {
    let title: String
    let query: String
    let width: CGFloat
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    let foregroundColor: Color
    let highlightColor: Color

    var body: some View {
        Text(attributedTitle)
            .font(.system(size: fontSize, weight: fontWeight))
            .lineLimit(1)
            .frame(width: width)
    }

    private var attributedTitle: AttributedString {
        var attributed = AttributedString(title)
        attributed.foregroundColor = foregroundColor
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return attributed
        }

        let lowerTitle = title.lowercased()
        let lowerQuery = trimmedQuery.lowercased()

        if let range = lowerTitle.range(of: lowerQuery) {
            let start = title.distance(from: title.startIndex, to: range.lowerBound)
            let end = title.distance(from: title.startIndex, to: range.upperBound)
            if let attributedRange = Range(NSRange(location: start, length: end - start), in: attributed) {
                attributed[attributedRange].foregroundColor = highlightColor
                attributed[attributedRange].font = .system(size: fontSize, weight: .semibold)
            }
        }
        return attributed
    }
}

private struct SearchCommandMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onRevealSelectedResult: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRevealSelectedResult: onRevealSelectedResult)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(isEnabled: isEnabled)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onRevealSelectedResult = onRevealSelectedResult
        context.coordinator.install(isEnabled: isEnabled)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onRevealSelectedResult: () -> Void
        private var monitor: Any?
        private var isInstalled = false

        init(onRevealSelectedResult: @escaping () -> Void) {
            self.onRevealSelectedResult = onRevealSelectedResult
        }

        func install(isEnabled: Bool) {
            guard isEnabled else {
                uninstall()
                return
            }

            guard !isInstalled else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let isReturn = event.keyCode == 36 || event.keyCode == 76
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if isReturn, flags == .command {
                    onRevealSelectedResult()
                    return nil
                }

                return event
            }
            isInstalled = true
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            isInstalled = false
        }

        deinit {
            uninstall()
        }
    }
}

private struct ShellLayoutMetrics {
    let iconFrame: CGFloat
    let labelWidth: CGFloat
    let cellHeight: CGFloat
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
    let folderTileSize: CGFloat
    let iconCornerRadius: CGFloat
    let folderCornerRadius: CGFloat

    var horizontalFootprint: CGFloat {
        labelWidth + columnSpacing
    }

    var verticalFootprint: CGFloat {
        cellHeight + rowSpacing
    }

    static let regular = ShellLayoutMetrics(
        iconFrame: 96,
        labelWidth: 120,
        cellHeight: 132,
        columnSpacing: 34,
        rowSpacing: 34,
        folderTileSize: 96,
        iconCornerRadius: 22,
        folderCornerRadius: 22
    )

    static let compact = ShellLayoutMetrics(
        iconFrame: 74,
        labelWidth: 100,
        cellHeight: 106,
        columnSpacing: 24,
        rowSpacing: 26,
        folderTileSize: 86,
        iconCornerRadius: 20,
        folderCornerRadius: 20
    )
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else {
            return isEmpty ? [] : [self]
        }

        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}

private struct AppIconImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageFrameStyle = .none
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = image
    }
}

private struct NativePageControllerHost: NSViewControllerRepresentable {
    let pageCount: Int
    @Binding var selection: Int
    let makePage: (Int) -> AnyView

    private var arrangedObjects: [Int] {
        Array(0..<max(pageCount, 1))
    }

    private var clampedSelection: Int {
        min(max(selection, 0), max(pageCount - 1, 0))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSViewController(context: Context) -> NSPageController {
        let controller = NSPageController()
        controller.delegate = context.coordinator
        controller.transitionStyle = .horizontalStrip
        controller.arrangedObjects = arrangedObjects
        controller.selectedIndex = clampedSelection
        return controller
    }

    func updateNSViewController(_ controller: NSPageController, context: Context) {
        context.coordinator.parent = self
        let existingObjects = controller.arrangedObjects as? [Int]
        if existingObjects != arrangedObjects {
            controller.arrangedObjects = arrangedObjects
        }

        if controller.selectedIndex != clampedSelection {
            controller.selectedIndex = clampedSelection
        }
    }

    final class Coordinator: NSObject, NSPageControllerDelegate {
        var parent: NativePageControllerHost

        init(parent: NativePageControllerHost) {
            self.parent = parent
        }

        func pageController(_ pageController: NSPageController, identifierFor object: Any) -> NSPageController.ObjectIdentifier {
            "page"
        }

        func pageController(_ pageController: NSPageController, viewControllerForIdentifier identifier: NSPageController.ObjectIdentifier) -> NSViewController {
            NativePageHostingController()
        }

        func pageController(_ pageController: NSPageController, prepare viewController: NSViewController, with object: Any?) {
            guard let host = viewController as? NativePageHostingController,
                  let page = object as? Int else {
                return
            }
            host.rootView = parent.makePage(page)
        }

        func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
            pageController.completeTransition()
            let selected = pageController.selectedIndex
            if parent.selection != selected {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.selection = selected
                }
            }
        }
    }
}

private final class NativePageHostingController: NSHostingController<AnyView> {
    init() {
        super.init(rootView: AnyView(EmptyView()))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

private struct SystemGlassSurface: NSViewRepresentable {
    let cornerRadius: CGFloat
    let style: NativeGlassVariant

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView()
            view.style = style.nsStyle
            view.cornerRadius = cornerRadius
            view.wantsLayer = true
            view.layer?.masksToBounds = true
            return view
        }

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = cornerRadius
        visualEffect.layer?.masksToBounds = true
        return visualEffect
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let glassView = nsView as? NSGlassEffectView {
            glassView.style = style.nsStyle
            glassView.cornerRadius = cornerRadius
        } else if let visualEffect = nsView as? NSVisualEffectView {
            visualEffect.layer?.cornerRadius = cornerRadius
        }
    }
}

enum NativeGlassVariant {
    case regular
    case clear

    @available(macOS 26.0, *)
    var nsStyle: NSGlassEffectView.Style {
        switch self {
        case .regular: .regular
        case .clear: .clear
        }
    }
}
