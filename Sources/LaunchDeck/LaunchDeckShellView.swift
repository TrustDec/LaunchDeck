import AppKit
import CryptoKit
import ImageIO
import SwiftUI

struct LaunchDeckShellView: View {
    @ObservedObject var store: LaunchDeckShellStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var pageColumns = 8
    @State private var pageRows = 6
    @State private var wallpaper: NSImage?
    @State private var activeFolder: LaunchItem?
    @State private var isFolderOverlayVisible = false
    @State private var pageDragOffset: CGFloat = 0

    private var metrics: ShellLayoutMetrics {
        store.compactMode ? .compact : .regular
    }

    private let horizontalInset: CGFloat = 20
    private let verticalChromeAllowance: CGFloat = 220
    private var isFolderMode: Bool { activeFolder != nil }
    private var isFolderPresented: Bool { activeFolder != nil && isFolderOverlayVisible }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundAtmosphere

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleCanvasTap()
                    }

                VStack(spacing: 22) {
                    topBar
                        .padding(.top, topBarTopPadding(for: proxy.size))

                    if store.isSearching {
                        searchResultsGrid(in: proxy.size)
                    } else {
                        pageGrid(in: proxy.size)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, horizontalInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .compositingGroup()
                .scaleEffect(isFolderPresented ? 0.96 : 1)
                .opacity(isFolderPresented ? 0 : 1)
                .allowsHitTesting(!isFolderMode)

                SearchCommandMonitor(
                    isEnabled: store.isSearching,
                    onRevealSelectedResult: {
                        store.revealSelectedSearchResultInFinder()
                    }
                )
                .allowsHitTesting(false)

                WheelPagingInputMonitor(
                    isEnabled: !store.isSearching && activeFolder == nil && store.pageCount > 1,
                    onPreviousPage: {
                        store.previousPage()
                    },
                    onNextPage: {
                        store.nextPage()
                    }
                )
                .allowsHitTesting(false)

                if let folder = activeFolder {
                    folderOverlay(for: folder, in: proxy.size)
                }
            }
            .task {
                await store.loadIfNeeded()
            }
            .onChange(of: store.query) { _, _ in
                store.syncSearchSelection()
            }
            .onChange(of: store.selectedFolder) { _, next in
                syncFolderOverlay(with: next)
            }
            .task(id: "\(Int(proxy.size.width))x\(Int(proxy.size.height))-\(store.compactMode)") {
                let preferredColumns = 8
                let preferredRows = 6
                let availableWidth = max(proxy.size.width - horizontalInset * 2, metrics.labelWidth)
                let availableHeight = max(proxy.size.height - verticalChromeAllowance, metrics.cellHeight)
                let fittedColumns = max(Int((availableWidth + metrics.columnSpacing) / metrics.horizontalFootprint), 1)
                let fittedRows = max(Int((availableHeight + metrics.rowSpacing) / metrics.verticalFootprint), 1)
                let columns = max(min(preferredColumns, fittedColumns), 1)
                let rows = max(min(preferredRows, fittedRows), 1)
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

    private func topBarTopPadding(for size: CGSize) -> CGFloat {
        _ = size
        return 100
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
        let contentWidth = max(size.width - horizontalInset * 2, 320)
        let contentHeight = CGFloat(pageRows) * metrics.cellHeight + CGFloat(max(pageRows - 1, 0)) * (metrics.rowSpacing - 6) + 8
        return VStack(spacing: 14) {
            NativePageControllerHost(
                pageCount: store.pageCount,
                selection: pageSelectionBinding,
                refreshToken: pageRefreshToken
            ) { page in
                let clampedPage = min(max(page, 0), max(store.pageCount - 1, 0))
                let pageItems = store.pagedItems[clampedPage]
                return AnyView(
                    pageCanvas(items: pageItems)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                )
            }
            .frame(height: contentHeight, alignment: .center)
            .offset(x: pageDragOffset)
            .contentShape(Rectangle())
            .simultaneousGesture(pageDragGesture(containerWidth: contentWidth))

            NativePageIndicator(pageCount: store.pageCount, selection: pageSelectionBinding)
                .frame(height: store.pageCount > 1 ? 24 : 0)
        }
        .frame(width: contentWidth, alignment: .center)
        .onChange(of: store.currentPage) { _, _ in
            if pageDragOffset != 0 {
                pageDragOffset = 0
            }
        }
        .onChange(of: activeFolder?.id) { _, _ in
            if pageDragOffset != 0 {
                pageDragOffset = 0
            }
        }
        .onChange(of: store.isSearching) { _, isSearching in
            if isSearching, pageDragOffset != 0 {
                pageDragOffset = 0
            }
        }
    }

    private var pageSelectionBinding: Binding<Int> {
        Binding(
            get: { min(max(store.currentPage, 0), max(store.pageCount - 1, 0)) },
            set: { store.selectPage($0) }
        )
    }

    private var pageRefreshToken: Int {
        var hasher = Hasher()
        hasher.combine(pageColumns)
        hasher.combine(pageRows)
        hasher.combine(store.pageCount)
        hasher.combine(store.items.count)
        hasher.combine(store.query)
        return hasher.finalize()
    }

    private func pageCanvas(items: [LaunchItem]) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    handleCanvasTap()
                }

            pageContent(items: items)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func pageContent(items: [LaunchItem]) -> some View {
        let rows = items.chunked(into: max(pageColumns, 1))
        let rowHeight = CGFloat(pageRows) * metrics.cellHeight + CGFloat(max(pageRows - 1, 0)) * (metrics.rowSpacing - 6)

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
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight, alignment: .top)
        .padding(.top, 8)
    }

    private func pageDragGesture(containerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !store.isSearching, activeFolder == nil, store.pageCount > 1 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                pageDragOffset = normalizedPageDragOffset(
                    for: value.translation.width,
                    containerWidth: containerWidth
                )
            }
            .onEnded { value in
                guard !store.isSearching, activeFolder == nil, store.pageCount > 1 else {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                        pageDragOffset = 0
                    }
                    return
                }

                let horizontal = value.translation.width
                guard abs(horizontal) > abs(value.translation.height) else {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                        pageDragOffset = 0
                    }
                    return
                }

                let predicted = value.predictedEndTranslation.width
                let effective = abs(predicted) > abs(horizontal) ? predicted : horizontal
                let threshold = min(max(containerWidth * 0.12, 70), 180)

                if effective <= -threshold {
                    store.nextPage()
                } else if effective >= threshold {
                    store.previousPage()
                }

                withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                    pageDragOffset = 0
                }
            }
    }

    private func normalizedPageDragOffset(for translation: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let maxOffset = min(max(containerWidth * 0.24, 90), 220)
        let atFirstPage = store.currentPage <= 0
        let atLastPage = store.currentPage >= store.pageCount - 1

        var adjusted = translation
        if (atFirstPage && translation > 0) || (atLastPage && translation < 0) {
            adjusted *= 0.36
        }

        return min(max(adjusted, -maxOffset), maxOffset)
    }

    private func folderOverlay(for folder: LaunchItem, in viewport: CGSize) -> some View {
        VStack(spacing: 18) {
            Text(folder.title)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Color(nsColor: .labelColor))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.14), radius: 8, y: 4)

            folderPanel(for: folder, in: viewport)
                .onTapGesture { }
        }
        .compositingGroup()
        .scaleEffect(isFolderOverlayVisible ? 1 : 1.08)
        .opacity(isFolderOverlayVisible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    store.closeFolder()
                }
        }
    }

    private func folderPanel(for folder: LaunchItem, in viewport: CGSize) -> some View {
        let resolvedFolder = store.items.first(where: { $0.id == folder.id && $0.isFolder }) ?? folder
        let itemCount = max(resolvedFolder.children.count, 1)
        let folderMetrics = metrics
        let tileSize: CGFloat = folderMetrics.labelWidth
        let spacingX: CGFloat = folderMetrics.columnSpacing
        let spacingY: CGFloat = max(folderMetrics.rowSpacing - 8, 16)
        let horizontalPadding: CGFloat = 34
        let verticalPadding: CGFloat = 28
        let maxPanelHeight = max(viewport.height - 220, 320)
        let fixedColumns = max(pageColumns, 1)
        let rows = max(Int(ceil(Double(itemCount) / Double(fixedColumns))), 1)
        let gridWidth = CGFloat(fixedColumns) * tileSize + CGFloat(max(fixedColumns - 1, 0)) * spacingX
        let gridHeight = CGFloat(rows) * folderMetrics.cellHeight + CGFloat(max(rows - 1, 0)) * spacingY + 2
        let panelWidth = min(gridWidth + horizontalPadding * 2, max(viewport.width - 40, 360))
        let panelHeight = min(max(gridHeight + verticalPadding * 2, 260), maxPanelHeight)
        let chunkedRows = resolvedFolder.children.chunked(into: fixedColumns)

        return VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: spacingY) {
                    ForEach(Array(chunkedRows.enumerated()), id: \.offset) { _, rowItems in
                        let emptyCount = max(fixedColumns - rowItems.count, 0)
                        let leadingSpacers = emptyCount / 2
                        let trailingSpacers = emptyCount - leadingSpacers

                        HStack(alignment: .top, spacing: spacingX) {
                            ForEach(0..<leadingSpacers, id: \.self) { _ in
                                Color.clear
                                    .frame(width: tileSize, height: folderMetrics.cellHeight)
                            }

                            ForEach(rowItems) { child in
                                Button {
                                    store.closeFolder()
                                    store.activate(child)
                                } label: {
                                    VStack(spacing: 10) {
                                        ShellIconTile(item: child, isActive: false, metrics: folderMetrics)
                                        Text(child.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(Color(nsColor: .labelColor))
                                            .lineLimit(1)
                                            .frame(width: tileSize)
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            ForEach(0..<trailingSpacers, id: \.self) { _ in
                                Color.clear
                                    .frame(width: tileSize, height: folderMetrics.cellHeight)
                            }
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(width: gridWidth + horizontalPadding * 2, alignment: .center)
            }
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .topLeading)
        .background {
            SystemGlassSurface(cornerRadius: 36, style: .regular)
        }
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.13 : 0.18),
                            Color.clear,
                            Color.black.opacity(colorScheme == .dark ? 0.16 : 0.08),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.23), lineWidth: 1)
        }
    }

    private func syncFolderOverlay(with nextFolder: LaunchItem?) {
        if let nextFolder {
            activeFolder = nextFolder
            withAnimation(.easeOut(duration: 0.34)) {
                isFolderOverlayVisible = true
            }
            return
        }

        guard activeFolder != nil else {
            return
        }

        withAnimation(.easeIn(duration: 0.28)) {
            isFolderOverlayVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            if store.selectedFolder == nil {
                activeFolder = nil
            }
        }
    }

    private func handleCanvasTap() {
        if store.selectedFolder != nil {
            store.closeFolder()
            return
        }
        NSApp.keyWindow?.close()
    }

}

private enum DesktopWallpaperLoader {
    private static let supportedImageExtensions: Set<String> = [
        "heic", "heif", "jpg", "jpeg", "png", "tif", "tiff", "webp", "bmp"
    ]

    static func loadAsync() async -> NSImage? {
        return await Task.detached(priority: .utility) {
            load()
        }.value
    }

    static func load() -> NSImage? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen) else {
            return nil
        }

        let effectiveURL = resolveCurrentWallpaperURLUsingPrivateCache(
            for: screen,
            wallpaperURL: wallpaperURL
        ) ?? wallpaperURL

        guard let imageURL = resolveWallpaperImageURL(from: effectiveURL) else {
            return nil
        }

        let pixelScale = max(screen.backingScaleFactor, 1)
        let maxDimension = max(screen.frame.width, screen.frame.height) * pixelScale
        return downsampledImage(at: imageURL, maxPixelSize: min(maxDimension, 2560))
    }

    private static func resolveWallpaperImageURL(from url: URL) -> URL? {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
            return nil
        }

        if values.isRegularFile == true {
            return url
        }

        if values.isDirectory == true {
            return latestImageURL(in: url)
        }

        return nil
    }

    private static func resolveCurrentWallpaperURLUsingPrivateCache(
        for screen: NSScreen,
        wallpaperURL: URL
    ) -> URL? {
        guard let values = try? wallpaperURL.resourceValues(forKeys: [.isDirectoryKey]) else {
            return nil
        }
        guard values.isDirectory == true else {
            return nil
        }

        let cacheDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(
                "Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches/extension-com.apple.wallpaper.extension.image",
                isDirectory: true
            )
        guard let cacheRecords = loadPrivateCacheRecords(from: cacheDirectory), !cacheRecords.isEmpty else {
            return nil
        }

        let pixelWidth = max(Int((screen.frame.width * max(screen.backingScaleFactor, 1)).rounded()), 1)
        let pixelHeight = max(Int((screen.frame.height * max(screen.backingScaleFactor, 1)).rounded()), 1)
        let relevantRecords = pickRelevantRecords(
            from: cacheRecords,
            targetWidth: pixelWidth,
            targetHeight: pixelHeight,
            maxCount: 24
        )
        guard !relevantRecords.isEmpty else {
            return nil
        }

        let wantedHashes = Set(relevantRecords.map(\.hash))
        let hashToPath = buildHashToImagePathMap(in: wallpaperURL, wantedHashes: wantedHashes)

        for record in relevantRecords {
            if let path = hashToPath[record.hash] {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    private struct PrivateCacheRecord {
        let hash: String
        let width: Int
        let height: Int
        let modifiedAt: Date
    }

    private static func loadPrivateCacheRecords(from directory: URL) -> [PrivateCacheRecord]? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var records: [PrivateCacheRecord] = []
        records.reserveCapacity(entries.count)

        for entry in entries where entry.pathExtension.lowercased() == "bmp" {
            guard let values = try? entry.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                continue
            }

            let stem = entry.deletingPathExtension().lastPathComponent
            let parts = stem.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let hash = String(parts[0])
            guard hash.count == 64,
                  let width = Int(parts[1]),
                  let height = Int(parts[2]) else {
                continue
            }

            records.append(
                PrivateCacheRecord(
                    hash: hash,
                    width: width,
                    height: height,
                    modifiedAt: values.contentModificationDate ?? .distantPast
                )
            )
        }

        if records.isEmpty {
            return nil
        }

        records.sort { $0.modifiedAt > $1.modifiedAt }
        return records
    }

    private static func pickRelevantRecords(
        from records: [PrivateCacheRecord],
        targetWidth: Int,
        targetHeight: Int,
        maxCount: Int
    ) -> [PrivateCacheRecord] {
        let exact = records.filter {
            ($0.width == targetWidth && $0.height == targetHeight)
                || ($0.width == targetHeight && $0.height == targetWidth)
        }

        if !exact.isEmpty {
            return Array(exact.prefix(maxCount))
        }

        let near = records.sorted {
            let lhsScore = abs($0.width - targetWidth) + abs($0.height - targetHeight)
            let rhsScore = abs($1.width - targetWidth) + abs($1.height - targetHeight)
            if lhsScore == rhsScore {
                return $0.modifiedAt > $1.modifiedAt
            }
            return lhsScore < rhsScore
        }
        return Array(near.prefix(maxCount))
    }

    private static func buildHashToImagePathMap(
        in directory: URL,
        wantedHashes: Set<String>
    ) -> [String: String] {
        guard !wantedHashes.isEmpty else {
            return [:]
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return [:]
        }

        var result: [String: String] = [:]
        result.reserveCapacity(min(wantedHashes.count, 16))

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard supportedImageExtensions.contains(ext),
                  let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                continue
            }

            let hash = sha256Hex(of: fileURL.path)
            if wantedHashes.contains(hash) {
                result[hash] = fileURL.path
                if result.count == wantedHashes.count {
                    break
                }
            }
        }

        return result
    }

    private static func sha256Hex(of text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func latestImageURL(in directory: URL) -> URL? {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .isHiddenKey,
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        var bestURL: URL?
        var bestDate: Date = .distantPast
        var visitedCount = 0

        for case let fileURL as URL in enumerator {
            visitedCount += 1
            if visitedCount > 4000 {
                break
            }

            let ext = fileURL.pathExtension.lowercased()
            guard supportedImageExtensions.contains(ext),
                  let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else {
                continue
            }

            let modified = values.contentModificationDate ?? .distantPast
            if modified >= bestDate {
                bestDate = modified
                bestURL = fileURL
            }
        }

        return bestURL
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

@MainActor
private enum AppIconCache {
    static let baseCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    static let sizedCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 768
        return cache
    }()

    static func image(for path: String, targetSize: CGFloat) -> NSImage {
        let normalizedSize = max(targetSize.rounded(.toNearestOrEven), 16)
        let sizedKey = "\(path)#\(Int(normalizedSize))" as NSString
        if let cached = sizedCache.object(forKey: sizedKey) {
            return cached
        }

        let base = baseImage(for: path)
        let rasterized = rasterize(base, targetSize: normalizedSize)
        sizedCache.setObject(rasterized, forKey: sizedKey)
        return rasterized
    }

    static func cachedImage(for path: String, targetSize: CGFloat) -> NSImage? {
        let normalizedSize = max(targetSize.rounded(.toNearestOrEven), 16)
        let sizedKey = "\(path)#\(Int(normalizedSize))" as NSString
        return sizedCache.object(forKey: sizedKey)
    }

    private static func baseImage(for path: String) -> NSImage {
        let key = path as NSString
        if let cached = baseCache.object(forKey: key) {
            return cached
        }
        let image = NSWorkspace.shared.icon(forFile: path)
        baseCache.setObject(image, forKey: key)
        return image
    }

    private static func rasterize(_ image: NSImage, targetSize: CGFloat) -> NSImage {
        let size = NSSize(width: targetSize, height: targetSize)
        let rendered = NSImage(size: size)
        rendered.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        rendered.unlockFocus()
        return rendered
    }
}

@MainActor
private struct ShellIconTile: View {
    let item: LaunchItem
    let isActive: Bool
    let metrics: ShellLayoutMetrics
    @State private var icon: NSImage?

    init(item: LaunchItem, isActive: Bool, metrics: ShellLayoutMetrics) {
        self.item = item
        self.isActive = isActive
        self.metrics = metrics
        if !item.isFolder, let path = item.bundleURL?.path {
            _icon = State(initialValue: AppIconCache.cachedImage(for: path, targetSize: metrics.iconFrame))
        } else {
            _icon = State(initialValue: nil)
        }
    }

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
        .task(id: "\(item.id.uuidString)-\(Int(metrics.iconFrame))") {
            guard !item.isFolder, let bundleURL = item.bundleURL else { return }
            if let cached = AppIconCache.cachedImage(for: bundleURL.path, targetSize: metrics.iconFrame) {
                icon = cached
                return
            }
            let resolved = AppIconCache.image(for: bundleURL.path, targetSize: metrics.iconFrame)
            if icon !== resolved {
                icon = resolved
            }
        }
    }
}

@MainActor
private struct MiniShellIcon: View {
    let bundleURL: URL?
    @State private var icon: NSImage?

    init(bundleURL: URL?) {
        self.bundleURL = bundleURL
        if let path = bundleURL?.path {
            _icon = State(initialValue: AppIconCache.cachedImage(for: path, targetSize: 24))
        } else {
            _icon = State(initialValue: nil)
        }
    }

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
        .task(id: "\(bundleURL?.path ?? "")-24") {
            guard let bundleURL else { return }
            if let cached = AppIconCache.cachedImage(for: bundleURL.path, targetSize: 24) {
                icon = cached
                return
            }
            let resolved = AppIconCache.image(for: bundleURL.path, targetSize: 24)
            if icon !== resolved {
                icon = resolved
            }
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
        iconFrame: 108,
        labelWidth: 130,
        cellHeight: 146,
        columnSpacing: 34,
        rowSpacing: 34,
        folderTileSize: 108,
        iconCornerRadius: 22,
        folderCornerRadius: 22
    )

    static let compact = ShellLayoutMetrics(
        iconFrame: 84,
        labelWidth: 108,
        cellHeight: 118,
        columnSpacing: 24,
        rowSpacing: 26,
        folderTileSize: 94,
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
        if nsView.image !== image {
            nsView.image = image
        }
    }
}

private struct NativePageControllerHost: NSViewControllerRepresentable {
    let pageCount: Int
    @Binding var selection: Int
    let refreshToken: Int
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
            if clampedSelection == controller.selectedIndex + 1 {
                controller.navigateForward(nil)
            } else if clampedSelection == controller.selectedIndex - 1 {
                controller.navigateBack(nil)
            } else {
                controller.selectedIndex = clampedSelection
            }
        }

        if controller.selectedIndex == clampedSelection {
            context.coordinator.refreshVisiblePageIfNeeded(
                in: controller,
                token: refreshToken
            )
        }
    }

    final class Coordinator: NSObject, NSPageControllerDelegate {
        var parent: NativePageControllerHost
        private var lastRefreshToken: Int?

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
            host.view.frame = pageController.view.bounds
            host.view.autoresizingMask = [.width, .height]
        }

        @MainActor
        func refreshVisiblePageIfNeeded(in pageController: NSPageController, token: Int) {
            guard lastRefreshToken != token else { return }
            lastRefreshToken = token
            guard let host = pageController.selectedViewController as? NativePageHostingController else {
                return
            }
            let page = min(max(pageController.selectedIndex, 0), max(parent.pageCount - 1, 0))
            host.rootView = parent.makePage(page)
            host.view.frame = pageController.view.bounds
            host.view.autoresizingMask = [.width, .height]
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

        func pageController(_ pageController: NSPageController, frameFor object: Any?) -> NSRect {
            pageController.view.bounds
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

private struct WheelPagingInputMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onPreviousPage: () -> Void
    let onNextPage: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPreviousPage: onPreviousPage, onNextPage: onNextPage)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(isEnabled: isEnabled)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onPreviousPage = onPreviousPage
        context.coordinator.onNextPage = onNextPage
        context.coordinator.install(isEnabled: isEnabled)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onPreviousPage: () -> Void
        var onNextPage: () -> Void
        private var monitor: Any?
        private var isInstalled = false
        private var lastTriggerTime: TimeInterval = 0
        private var accumulatedDelta: CGFloat = 0
        private var accumulatedDirection: CGFloat = 0
        private var lastEventTime: TimeInterval = 0
        private var preciseGestureLocked = false

        init(
            onPreviousPage: @escaping () -> Void,
            onNextPage: @escaping () -> Void
        ) {
            self.onPreviousPage = onPreviousPage
            self.onNextPage = onNextPage
        }

        func install(isEnabled: Bool) {
            guard isEnabled else {
                uninstall()
                return
            }

            guard !isInstalled else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }

                let now = ProcessInfo.processInfo.systemUptime
                let dominantDelta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                    ? event.scrollingDeltaX
                    : event.scrollingDeltaY

                if event.hasPreciseScrollingDeltas {
                    if event.phase == .began {
                        resetAccumulation(lockPrecise: false)
                    }

                    if event.phase == .ended || event.phase == .cancelled {
                        resetAccumulation(lockPrecise: false)
                        return event
                    }

                    if event.momentumPhase != [] {
                        return nil
                    }

                    if preciseGestureLocked {
                        return nil
                    }
                }

                if now - lastEventTime > 0.3 {
                    resetAccumulation(lockPrecise: false)
                }
                lastEventTime = now

                let minimumInterval: TimeInterval = event.hasPreciseScrollingDeltas ? 0.1 : 0.12
                if now - lastTriggerTime < minimumInterval {
                    return event
                }

                guard dominantDelta != 0 else {
                    return event
                }

                if accumulatedDirection == 0 || dominantDelta.sign != accumulatedDirection.sign {
                    accumulatedDelta = 0
                }
                accumulatedDirection = dominantDelta
                accumulatedDelta += dominantDelta

                let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 4.5 : 0.95
                guard abs(accumulatedDelta) >= threshold else {
                    return event
                }

                lastTriggerTime = now
                if event.hasPreciseScrollingDeltas {
                    preciseGestureLocked = true
                }
                triggerPageChange(with: accumulatedDelta)
                accumulatedDelta = 0

                return nil
            }
            isInstalled = true
        }

        private func triggerPageChange(with dominantDelta: CGFloat) {
            // Match mouse wheel intuition: scroll up -> previous page, scroll down -> next page.
            if dominantDelta > 0 {
                onPreviousPage()
            } else {
                onNextPage()
            }
        }

        private func resetAccumulation(lockPrecise: Bool) {
            accumulatedDelta = 0
            accumulatedDirection = 0
            preciseGestureLocked = lockPrecise
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

private struct NativePageIndicator: View {
    let pageCount: Int
    @Binding var selection: Int

    var body: some View {
        if pageCount > 1 {
            HStack(spacing: 9) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Button {
                        selection = index
                    } label: {
                        Circle()
                            .fill(
                                index == selection
                                    ? Color.white.opacity(0.95)
                                    : Color.white.opacity(0.34)
                            )
                            .frame(width: index == selection ? 8 : 6, height: index == selection ? 8 : 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                SystemGlassSurface(cornerRadius: 12, style: .clear)
            }
            .clipShape(Capsule())
        }
    }
}

private struct MouseDragPagingInputMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onPreviousPage: () -> Void
    let onNextPage: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPreviousPage: onPreviousPage, onNextPage: onNextPage)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(isEnabled: isEnabled)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onPreviousPage = onPreviousPage
        context.coordinator.onNextPage = onNextPage
        context.coordinator.install(isEnabled: isEnabled)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onPreviousPage: () -> Void
        var onNextPage: () -> Void
        private var downMonitor: Any?
        private var dragMonitor: Any?
        private var upMonitor: Any?
        private var isInstalled = false
        private var isDragging = false
        private var hasTriggered = false
        private var dragStart: NSPoint = .zero

        init(
            onPreviousPage: @escaping () -> Void,
            onNextPage: @escaping () -> Void
        ) {
            self.onPreviousPage = onPreviousPage
            self.onNextPage = onNextPage
        }

        func install(isEnabled: Bool) {
            guard isEnabled else {
                uninstall()
                return
            }

            guard !isInstalled else {
                return
            }

            downMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self else { return event }
                isDragging = true
                hasTriggered = false
                dragStart = event.locationInWindow
                return event
            }

            dragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
                guard let self else { return event }
                guard isDragging, !hasTriggered else { return event }

                let deltaX = event.locationInWindow.x - dragStart.x
                let deltaY = event.locationInWindow.y - dragStart.y
                guard abs(deltaX) > abs(deltaY), abs(deltaX) >= 40 else {
                    return event
                }

                hasTriggered = true
                deltaX < 0 ? onNextPage() : onPreviousPage()
                return nil
            }

            upMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                guard let self else { return event }
                isDragging = false
                hasTriggered = false
                return event
            }

            isInstalled = true
        }

        func uninstall() {
            if let downMonitor {
                NSEvent.removeMonitor(downMonitor)
            }
            if let dragMonitor {
                NSEvent.removeMonitor(dragMonitor)
            }
            if let upMonitor {
                NSEvent.removeMonitor(upMonitor)
            }
            downMonitor = nil
            dragMonitor = nil
            upMonitor = nil
            isInstalled = false
            isDragging = false
            hasTriggered = false
        }

        deinit {
            uninstall()
        }
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
