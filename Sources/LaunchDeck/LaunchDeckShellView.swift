import AppKit
import SwiftUI

struct LaunchDeckShellView: View {
    @ObservedObject var store: LaunchDeckShellStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var pageColumns = 6
    @State private var pageRows = 5
    @State private var renamingItem: LaunchItem?
    @State private var renameDraft = ""
    @State private var pageDragOffset: CGFloat = 0

    private var metrics: ShellLayoutMetrics {
        store.compactMode ? .compact : .regular
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundAtmosphere

                if store.selectedFolder != nil {
                    Color.black
                        .opacity(colorScheme == .dark ? 0.2 : 0.08)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                VStack(spacing: 28) {
                    topBar
                        .padding(.top, 30)

                    if store.isSearching {
                        searchResultsGrid(in: proxy.size)
                    } else {
                        pageGrid(in: proxy.size)
                            .offset(x: pageDragOffset)
                            .gesture(pageDragGesture)
                        pageDots
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 36)
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: store.selectedFolder?.id)
                .animation(.easeInOut(duration: 0.2), value: store.isSearching)

                if store.isEditing && !store.isSearching {
                    edgePagingDropZones
                }

                if store.isEditing {
                    editModeBadge
                        .padding(.top, 96)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ShellPagingInputMonitor(
                    onPreviousPage: {
                        guard store.selectedFolder == nil else { return }
                        store.previousPage()
                    },
                    onNextPage: {
                        guard store.selectedFolder == nil else { return }
                        store.nextPage()
                    }
                )
                .allowsHitTesting(false)
            }
            .task {
                await store.loadIfNeeded()
            }
            .task(id: "\(Int(proxy.size.width))x\(Int(proxy.size.height))-\(store.compactMode)") {
                let columns = max(min(Int((proxy.size.width - 120) / metrics.horizontalFootprint), 9), 5)
                let rows = max(min(Int((proxy.size.height - 240) / metrics.verticalFootprint), 7), 4)
                pageColumns = columns
                pageRows = rows
                store.updatePageCapacity(columns * rows)
            }
            .onMoveCommand { direction in
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
            .onExitCommand {
                store.handleExitCommand()
            }
            .sheet(item: $renamingItem) { item in
                renameSheet(for: item)
            }
        }
    }

    private var backgroundAtmosphere: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)]
                    : [Color(nsColor: .windowBackgroundColor), Color(nsColor: .controlBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(nsColor: .controlAccentColor).opacity(colorScheme == .dark ? 0.17 : 0.12),
                    .clear,
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 520
            )
            .blendMode(.plusLighter)

            RadialGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.08 : 0.14),
                    .clear,
                ],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 460
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.02 : 0.06),
                    Color.clear,
                    Color.black.opacity(colorScheme == .dark ? 0.18 : 0.05),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
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
                            ShellIconTile(item: item, isActive: item.id == store.selectedFolder?.id, isEditing: store.isEditing, metrics: metrics)

                            Text(item.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(nsColor: .labelColor))
                                .lineLimit(1)
                                .frame(width: metrics.labelWidth)
                        }
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.45)
                            .onEnded { _ in
                                store.setEditing(true)
                            }
                    )
                    .contextMenu {
                        itemContextMenu(for: item, isTopLevel: true)
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
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    private var topBar: some View {
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

            if store.isEditing {
                Button("Done") {
                    store.setEditing(false)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: .labelColor))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background {
                    SystemGlassSurface(cornerRadius: 18, style: .regular)
                }
                .clipShape(Capsule())
            } else {
                Button("Edit") {
                    store.setEditing(true)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: .labelColor))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background {
                    SystemGlassSurface(cornerRadius: 18, style: .regular)
                }
                .clipShape(Capsule())
            }

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
        .frame(maxWidth: 720)
    }

    private var editModeBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 13, weight: .semibold))
            Text("Editing Layout")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color(nsColor: .labelColor))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            SystemGlassSurface(cornerRadius: 16, style: .regular)
        }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.16 : 0.06), radius: 18, y: 10)
    }

    private func pageGrid(in size: CGSize) -> some View {
        let rows = store.visibleItems.chunked(into: pageColumns)
        let rowHeight = CGFloat(pageRows) * metrics.cellHeight + CGFloat(max(pageRows - 1, 0)) * metrics.rowSpacing
        let selectedFolderID = store.selectedFolder?.id

        return ZStack {
            VStack(alignment: .center, spacing: metrics.rowSpacing - 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, rowItems in
                    VStack(spacing: 18) {
                        HStack(alignment: .top, spacing: metrics.columnSpacing) {
                            ForEach(rowItems) { item in
                                Button {
                                    store.activate(item)
                                } label: {
                                    VStack(spacing: 10) {
                                        ShellIconTile(item: item, isActive: item.id == selectedFolderID, isEditing: store.isEditing, metrics: metrics)

                                        Text(item.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(Color(nsColor: .labelColor))
                                            .lineLimit(1)
                                            .frame(width: metrics.labelWidth)
                                    }
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(
                                    LongPressGesture(minimumDuration: 0.45)
                                        .onEnded { _ in
                                            store.setEditing(true)
                                        }
                                )
                                .applyIf(store.isEditing) { view in
                                    view.draggable(item.id.uuidString) {
                                        Color.clear.frame(width: 1, height: 1)
                                    }
                                }
                                .applyIf(store.isEditing) { view in
                                    view.dropDestination(for: String.self) { items, _ in
                                        guard let draggedID = items.first.flatMap(UUID.init(uuidString:)) else {
                                            return false
                                        }
                                        store.handleTopLevelDrop(draggedID: draggedID, onto: item.id)
                                        return true
                                    }
                                }
                                .contextMenu {
                                    itemContextMenu(for: item, isTopLevel: true)
                                }
                            }

                            ForEach(rowItems.count..<pageColumns, id: \.self) { _ in
                                Color.clear
                                    .frame(width: metrics.labelWidth, height: metrics.cellHeight)
                            }
                        }

                        if let folder = selectedFolder(in: rowItems) {
                            folderPanel(for: folder)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                                    removal: .scale(scale: 0.98).combined(with: .opacity)
                                ))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: rowHeight, alignment: .top)
            .padding(.top, 8)
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: selectedFolderID)
        }
    }

    private var pageDragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      store.selectedFolder == nil,
                      !store.isEditing
                else {
                    return
                }
                pageDragOffset = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      store.selectedFolder == nil,
                      !store.isEditing
                else {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                        pageDragOffset = 0
                    }
                    return
                }

                let threshold: CGFloat = 90
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    if value.translation.width > threshold {
                        store.previousPage()
                    } else if value.translation.width < -threshold {
                        store.nextPage()
                    }
                    pageDragOffset = 0
                }
            }
    }

    private var edgePagingDropZones: some View {
        HStack {
            edgeDropZone(direction: .left)
            Spacer()
            edgeDropZone(direction: .right)
        }
        .padding(.horizontal, 8)
    }

    private func edgeDropZone(direction: MoveCommandDirection) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.clear)
            .frame(width: 36)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                guard let draggedID = items.first.flatMap(UUID.init(uuidString:)) else {
                    return false
                }

                switch direction {
                case .left:
                    store.moveTopLevelItem(id: draggedID, pageDelta: -1)
                case .right:
                    store.moveTopLevelItem(id: draggedID, pageDelta: 1)
                default:
                    return false
                }
                return true
            }
    }

    private var pageDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<store.pageCount, id: \.self) { page in
                Button {
                    store.selectPage(page)
                } label: {
                    Capsule()
                        .fill(Color(nsColor: .labelColor).opacity(page == store.currentPage ? 0.92 : 0.22))
                        .frame(width: page == store.currentPage ? 18 : 8, height: 8)
                }
                .buttonStyle(.plain)
                .applyIf(store.isEditing) { view in
                    view.dropDestination(for: String.self) { items, _ in
                        guard let draggedID = items.first.flatMap(UUID.init(uuidString:)) else {
                            return false
                        }
                        store.moveTopLevelItem(id: draggedID, toPage: page)
                        return true
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background {
            SystemGlassSurface(cornerRadius: 18, style: .regular)
        }
        .clipShape(Capsule())
    }

    private func folderPanel(for folder: LaunchItem) -> some View {
        let itemCount = max(folder.children.count, 1)
        let columns = min(max(Int(ceil(sqrt(Double(itemCount)))), 1), 4)
        let rows = Int(ceil(Double(itemCount) / Double(columns)))
        let tileSize: CGFloat = metrics.folderTileSize
        let horizontalSpacing: CGFloat = 22
        let verticalSpacing: CGFloat = 24
        let gridWidth = CGFloat(columns) * tileSize + CGFloat(max(columns - 1, 0)) * horizontalSpacing
        let gridHeight = CGFloat(rows) * (tileSize + 28) + CGFloat(max(rows - 1, 0)) * verticalSpacing

        return VStack(spacing: 24) {
            Text(folder.title)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color(nsColor: .labelColor))

            let gridColumns = Array(repeating: GridItem(.fixed(tileSize), spacing: horizontalSpacing), count: columns)

            LazyVGrid(columns: gridColumns, spacing: verticalSpacing) {
                ForEach(folder.children) { child in
                    Button {
                        store.activate(child)
                    } label: {
                        VStack(spacing: 10) {
                            ShellIconTile(item: child, isActive: false, isEditing: store.isEditing, metrics: metrics)

                            Text(child.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(nsColor: .labelColor))
                                .lineLimit(1)
                                .frame(width: tileSize)
                        }
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.45)
                            .onEnded { _ in
                                store.setEditing(true)
                            }
                    )
                    .applyIf(store.isEditing) { view in
                        view.draggable(child.id.uuidString) {
                            Color.clear.frame(width: 1, height: 1)
                        }
                    }
                    .applyIf(store.isEditing) { view in
                        view.dropDestination(for: String.self) { items, _ in
                            guard let draggedID = items.first.flatMap(UUID.init(uuidString:)) else {
                                return false
                            }
                            store.reorderItemWithinFolder(draggedID: draggedID, targetID: child.id, folderID: folder.id)
                            return true
                        }
                    }
                    .contextMenu {
                        itemContextMenu(for: child, isTopLevel: false)
                    }
                }
            }
            .frame(width: gridWidth, height: gridHeight, alignment: .top)

            Button("Close Folder") {
                store.closeFolder()
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                SystemGlassSurface(cornerRadius: 16, style: .clear)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 28)
        .frame(width: gridWidth + 68, alignment: .top)
        .background {
            SystemGlassSurface(cornerRadius: 30, style: .regular)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 28, y: 18)
    }

    private func selectedFolder(in rowItems: [LaunchItem]) -> LaunchItem? {
        guard let selectedFolder = store.selectedFolder else {
            return nil
        }

        return rowItems.first(where: { $0.id == selectedFolder.id })
    }

    @ViewBuilder
    private func itemContextMenu(for item: LaunchItem, isTopLevel: Bool) -> some View {
        Button("Rename") {
            renameDraft = item.title
            renamingItem = item
        }

        Button(item.isFolder ? "Hide Folder" : "Hide App") {
            store.hideItem(id: item.id)
        }

        if item.isFolder {
            Divider()

            Button("Dissolve Folder") {
                store.dissolveFolder(id: item.id)
            }
        }

        if isTopLevel {
            Divider()

            Button("Move To Previous Page") {
                store.moveTopLevelItem(id: item.id, pageDelta: -1)
            }

            Button("Move To Next Page") {
                store.moveTopLevelItem(id: item.id, pageDelta: 1)
            }
        } else {
            Divider()

            Button("Move Out of Folder") {
                store.ungroupItem(id: item.id)
            }
        }
    }

    private func renameSheet(for item: LaunchItem) -> some View {
        VStack(spacing: 20) {
            Text(item.isFolder ? "Rename Folder" : "Rename App")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(nsColor: .labelColor))

            TextField("Name", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)

            HStack(spacing: 12) {
                Button("Cancel") {
                    renamingItem = nil
                    renameDraft = ""
                }

                Button("Save") {
                    store.renameItem(id: item.id, title: renameDraft)
                    renamingItem = nil
                    renameDraft = ""
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ShellIconTile: View {
    let item: LaunchItem
    let isActive: Bool
    let isEditing: Bool
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
        .scaleEffect(isEditing ? 0.985 : 1)
        .animation(.easeOut(duration: 0.16), value: isEditing)
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
        iconFrame: 78,
        labelWidth: 108,
        cellHeight: 108,
        columnSpacing: 28,
        rowSpacing: 30,
        folderTileSize: 92,
        iconCornerRadius: 20,
        folderCornerRadius: 22
    )

    static let compact = ShellLayoutMetrics(
        iconFrame: 64,
        labelWidth: 92,
        cellHeight: 92,
        columnSpacing: 22,
        rowSpacing: 24,
        folderTileSize: 84,
        iconCornerRadius: 18,
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

private extension View {
    @ViewBuilder
    func applyIf<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
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

private struct ShellPagingInputMonitor: NSViewRepresentable {
    let onPreviousPage: () -> Void
    let onNextPage: () -> Void

    func makeNSView(context: Context) -> ShellPagingInputView {
        let view = ShellPagingInputView()
        view.onPreviousPage = onPreviousPage
        view.onNextPage = onNextPage
        return view
    }

    func updateNSView(_ nsView: ShellPagingInputView, context: Context) {
        nsView.onPreviousPage = onPreviousPage
        nsView.onNextPage = onNextPage
    }
}

private final class ShellPagingInputView: NSView {
    var onPreviousPage: (() -> Void)?
    var onNextPage: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func scrollWheel(with event: NSEvent) {
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY

        if abs(deltaX) >= abs(deltaY), abs(deltaX) > 4 {
            deltaX > 0 ? onNextPage?() : onPreviousPage?()
            return
        }

        guard abs(deltaY) > 4 else {
            return
        }

        deltaY > 0 ? onNextPage?() : onPreviousPage?()
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
