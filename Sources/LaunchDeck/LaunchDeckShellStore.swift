import AppKit
import Foundation

@MainActor
final class LaunchDeckShellStore: ObservableObject {
    private enum DefaultsKey {
        static let compactMode = "LaunchDeck.compactMode"
        static let hiddenItems = "LaunchDeck.hiddenItems"
    }

    @Published private(set) var items: [LaunchItem] = []
    @Published var query = ""
    @Published var selectedFolder: LaunchItem?
    @Published private(set) var isLoading = false
    @Published var currentPage = 0
    @Published var compactMode = UserDefaults.standard.bool(forKey: DefaultsKey.compactMode)
    @Published private(set) var hiddenItems: [LaunchItem]
    @Published var isEditing = false
    @Published var selectedSearchResultID: UUID?

    private let persistence: LaunchDeckPersistenceController
    private(set) var pageSize = 30

    init(persistence: LaunchDeckPersistenceController) {
        self.persistence = persistence
        hiddenItems = Self.loadHiddenItems()
        if let layout = persistence.loadLayout() {
            items = layout
        } else if let snapshot = persistence.loadSnapshot() {
            items = snapshot.items.map { $0.materialize() }
        }
    }

    var filteredItems: [LaunchItem] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return items }

        return items.filter { item in
            item.searchableText.contains(normalized)
        }
    }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var pagedItems: [[LaunchItem]] {
        guard !filteredItems.isEmpty else {
            return [[]]
        }

        return stride(from: 0, to: filteredItems.count, by: pageSize).map { start in
            let end = min(start + pageSize, filteredItems.count)
            return Array(filteredItems[start..<end])
        }
    }

    var pageCount: Int {
        pagedItems.count
    }

    var visibleItems: [LaunchItem] {
        pagedItems[min(max(currentPage, 0), max(pageCount - 1, 0))]
    }

    var primarySearchResult: LaunchItem? {
        if let selectedSearchResult,
           let selectedFolder {
            return selectedFolder.children.first(where: { $0.id == selectedSearchResult.id }) ?? selectedFolder.children.first
        }
        if let selectedSearchResult {
            return filteredItems.first(where: { $0.id == selectedSearchResult.id }) ?? filteredItems.first
        }
        return filteredItems.first
    }

    var selectedSearchResult: LaunchItem? {
        guard let selectedSearchResultID else {
            return nil
        }
        return filteredItems.first(where: { $0.id == selectedSearchResultID })
    }

    func loadIfNeeded() async {
        guard items.isEmpty, !isLoading else {
            return
        }

        await reload()
    }

    func reload() async {
        isLoading = true
        let imported = await Task.detached(priority: .utility) {
            SystemLaunchpadImportService.importItems()
        }.value
        let catalog: [LaunchItem]
        if let imported, !imported.isEmpty {
            catalog = imported
        } else {
            let scanned = await Task.detached(priority: .utility) {
                ShellAppCatalogScanner.scan()
            }.value
            catalog = scanned.isEmpty ? LaunchItem.demoCatalog : ShellAppFolderBuilder.bootstrapCatalog(from: scanned)
        }
        items = catalog
        currentPage = 0
        persistence.saveLayout(items: catalog)
        persistence.saveSnapshot(items: catalog)
        isLoading = false
    }

    func syncSearchSelection() {
        guard isSearching else {
            selectedSearchResultID = nil
            return
        }

        if let selectedSearchResultID,
           filteredItems.contains(where: { $0.id == selectedSearchResultID }) {
            return
        }

        selectedSearchResultID = filteredItems.first?.id
    }

    func reloadFromUI() {
        Task { @MainActor in
            await reload()
        }
    }

    func activate(_ item: LaunchItem) {
        if isEditing {
            if item.isFolder {
                selectedFolder = selectedFolder?.id == item.id ? nil : item
            }
            return
        }

        if item.isFolder {
            selectedFolder = item
            return
        }

        guard let bundleURL = item.bundleURL else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
    }

    func closeFolder() {
        selectedFolder = nil
    }

    func renameItem(id: UUID, title: String) {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        items = items.mapRecursively { item in
            guard item.id == id else { return item }
            return item.updatingTitle(normalized)
        }
        refreshSelectedFolder()
        persistCurrentLayout()
    }

    func hideItem(id: UUID) {
        guard let hiddenItem = items.findItem(id: id) else {
            return
        }

        items = items.removingItemRecursively(id: id)
        hiddenItems.removeAll { $0.id == id }
        hiddenItems.insert(hiddenItem, at: 0)
        currentPage = min(currentPage, max(pageCount - 1, 0))
        refreshSelectedFolder()
        persistCurrentLayout()
        persistHiddenItems()
    }

    func moveTopLevelItem(id: UUID, pageDelta: Int) {
        guard let currentIndex = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        let currentPageIndex = currentIndex / pageSize
        let targetPageIndex = min(max(currentPageIndex + pageDelta, 0), max(pageCount - 1, 0))
        guard targetPageIndex != currentPageIndex else {
            return
        }

        var reordered = items
        let item = reordered.remove(at: currentIndex)
        let rawTargetIndex = targetPageIndex * pageSize
        let targetIndex = min(max(rawTargetIndex, 0), reordered.count)
        reordered.insert(item, at: targetIndex)
        items = reordered
        currentPage = min(currentPage, max(pageCount - 1, 0))
        refreshSelectedFolder()
        persistCurrentLayout()
    }

    func moveTopLevelItem(id: UUID, toPage page: Int) {
        guard let currentIndex = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        let targetPage = min(max(page, 0), max(pageCount - 1, 0))
        let currentPageIndex = currentIndex / pageSize
        guard targetPage != currentPageIndex else {
            currentPage = targetPage
            return
        }

        var reordered = items
        let item = reordered.remove(at: currentIndex)
        let targetIndex = min(max(targetPage * pageSize, 0), reordered.count)
        reordered.insert(item, at: targetIndex)
        items = reordered
        currentPage = targetPage
        refreshSelectedFolder()
        persistCurrentLayout()
    }

    func ungroupItem(id: UUID) {
        guard let result = items.removingChildFromTopLevelFolder(id: id) else {
            return
        }

        items = result.items
        refreshSelectedFolder()
        persistCurrentLayout()
    }

    func dissolveFolder(id: UUID) {
        guard let result = items.dissolvingTopLevelFolder(id: id) else {
            return
        }

        items = result
        if selectedFolder?.id == id {
            selectedFolder = nil
        } else {
            refreshSelectedFolder()
        }
        currentPage = min(currentPage, max(pageCount - 1, 0))
        persistCurrentLayout()
    }

    func reorderItemWithinFolder(draggedID: UUID, targetID: UUID, folderID: UUID) {
        guard draggedID != targetID else {
            return
        }

        items = items.mapRecursively { item in
            guard item.id == folderID,
                  let draggedIndex = item.children.firstIndex(where: { $0.id == draggedID }),
                  let targetIndex = item.children.firstIndex(where: { $0.id == targetID })
            else {
                return item
            }

            var children = item.children
            let draggedItem = children.remove(at: draggedIndex)
            let normalizedTarget = min(max(targetIndex, 0), children.count)
            children.insert(draggedItem, at: normalizedTarget)
            return item.updatingChildren(children)
        }

        refreshSelectedFolder()
        persistCurrentLayout()
    }

    func restoreHiddenItem(id: UUID) {
        guard let hiddenIndex = hiddenItems.firstIndex(where: { $0.id == id }) else {
            return
        }

        let item = hiddenItems.remove(at: hiddenIndex)
        items.insert(item, at: 0)
        currentPage = 0
        persistCurrentLayout()
        persistHiddenItems()
    }

    func restoreAllHiddenItems() {
        guard !hiddenItems.isEmpty else {
            return
        }

        items.insert(contentsOf: hiddenItems, at: 0)
        hiddenItems.removeAll()
        currentPage = 0
        persistCurrentLayout()
        persistHiddenItems()
    }

    func resetLayoutFromSystem() {
        Task { @MainActor in
            await reload()
        }
    }

    func updatePageCapacity(_ capacity: Int) {
        let normalized = max(capacity, 1)
        guard pageSize != normalized else {
            return
        }

        pageSize = normalized
        currentPage = min(currentPage, max(pageCount - 1, 0))
    }

    func selectPage(_ page: Int) {
        currentPage = min(max(page, 0), max(pageCount - 1, 0))
    }

    func nextPage() {
        selectPage(currentPage + 1)
    }

    func previousPage() {
        selectPage(currentPage - 1)
    }

    func handleExitCommand() {
        if selectedFolder != nil {
            closeFolder()
        } else if isEditing {
            isEditing = false
        } else {
            NSApp.keyWindow?.close()
            NSApp.hide(nil)
        }
    }

    func toggleCompactMode() {
        compactMode.toggle()
        UserDefaults.standard.set(compactMode, forKey: DefaultsKey.compactMode)
    }

    func selectNextSearchResult() {
        guard isSearching, !filteredItems.isEmpty else {
            return
        }

        guard let selectedSearchResultID,
              let currentIndex = filteredItems.firstIndex(where: { $0.id == selectedSearchResultID })
        else {
            selectedSearchResultID = filteredItems.first?.id
            return
        }

        let nextIndex = min(currentIndex + 1, filteredItems.count - 1)
        selectedSearchResultID = filteredItems[nextIndex].id
    }

    func selectPreviousSearchResult() {
        guard isSearching, !filteredItems.isEmpty else {
            return
        }

        guard let selectedSearchResultID,
              let currentIndex = filteredItems.firstIndex(where: { $0.id == selectedSearchResultID })
        else {
            selectedSearchResultID = filteredItems.first?.id
            return
        }

        let previousIndex = max(currentIndex - 1, 0)
        selectedSearchResultID = filteredItems[previousIndex].id
    }

    func setEditing(_ isEditing: Bool) {
        self.isEditing = isEditing
        if !isEditing, selectedFolder?.children.isEmpty == true {
            selectedFolder = nil
        }
    }

    func handleTopLevelDrop(draggedID: UUID, onto targetID: UUID) {
        guard draggedID != targetID,
              let draggedIndex = items.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = items.firstIndex(where: { $0.id == targetID })
        else {
            return
        }

        let draggedItem = items[draggedIndex]
        let targetItem = items[targetIndex]

        if targetItem.isFolder {
            var updatedItems = items
            let normalizedDraggedIndex = draggedIndex > targetIndex ? draggedIndex : draggedIndex
            updatedItems.remove(at: normalizedDraggedIndex)
            guard let refreshedTargetIndex = updatedItems.firstIndex(where: { $0.id == targetID }) else {
                return
            }
            let updatedFolder = updatedItems[refreshedTargetIndex].updatingChildren(
                updatedItems[refreshedTargetIndex].children + [draggedItem]
            )
            updatedItems[refreshedTargetIndex] = updatedFolder
            items = updatedItems
        } else if !draggedItem.isFolder, !targetItem.isFolder {
            var updatedItems = items
            let firstIndex = min(draggedIndex, targetIndex)
            let secondIndex = max(draggedIndex, targetIndex)
            let firstItem = updatedItems.remove(at: secondIndex)
            let secondItem = updatedItems.remove(at: firstIndex)
            let folder = LaunchItem.folder(
                title: "Folder",
                children: [secondItem, firstItem]
            )
            updatedItems.insert(folder, at: firstIndex)
            items = updatedItems
        } else {
            var reordered = items
            let draggedItem = reordered.remove(at: draggedIndex)
            guard let refreshedTargetIndex = reordered.firstIndex(where: { $0.id == targetID }) else {
                return
            }
            reordered.insert(draggedItem, at: refreshedTargetIndex)
            items = reordered
        }

        refreshSelectedFolder()
        persistCurrentLayout()
    }

    private func persistCurrentLayout() {
        persistence.saveLayout(items: items)
        persistence.saveSnapshot(items: items)
    }

    private func persistHiddenItems() {
        let snapshots = hiddenItems.map(LaunchItemSnapshot.init)
        let payload = try? JSONEncoder().encode(snapshots)
        UserDefaults.standard.set(payload, forKey: DefaultsKey.hiddenItems)
    }

    private func refreshSelectedFolder() {
        guard let selectedFolder else {
            return
        }
        self.selectedFolder = items.findItem(id: selectedFolder.id)
    }

    private static func loadHiddenItems() -> [LaunchItem] {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.hiddenItems),
              let snapshots = try? JSONDecoder().decode([LaunchItemSnapshot].self, from: data)
        else {
            return []
        }

        return snapshots.map { $0.materialize() }
    }
}

private extension Array where Element == LaunchItem {
    func mapRecursively(_ transform: (LaunchItem) -> LaunchItem) -> [LaunchItem] {
        map { item in
            let transformedChildren = item.children.mapRecursively(transform)
            let transformedItem = item.children == transformedChildren ? item : item.updatingChildren(transformedChildren)
            return transform(transformedItem)
        }
    }

    func removingItemRecursively(id: UUID) -> [LaunchItem] {
        compactMap { item in
            guard item.id != id else {
                return nil
            }

            let children = item.children.removingItemRecursively(id: id)
            return children == item.children ? item : item.updatingChildren(children)
        }
    }

    func findItem(id: UUID) -> LaunchItem? {
        for item in self {
            if item.id == id {
                return item
            }
            if let nested = item.children.findItem(id: id) {
                return nested
            }
        }
        return nil
    }

    func removingChildFromTopLevelFolder(id: UUID) -> (items: [LaunchItem], movedItem: LaunchItem)? {
        for (index, item) in enumerated() where item.isFolder {
            guard let childIndex = item.children.firstIndex(where: { $0.id == id }) else {
                continue
            }

            let movedItem = item.children[childIndex]
            var updatedItems = self
            var folderChildren = item.children
            folderChildren.remove(at: childIndex)

            updatedItems.remove(at: index)

            if folderChildren.isEmpty {
                updatedItems.insert(movedItem, at: index)
            } else if folderChildren.count == 1 {
                updatedItems.insert(folderChildren[0], at: index)
                updatedItems.insert(movedItem, at: Swift.min(index + 1, updatedItems.count))
            } else {
                updatedItems.insert(item.updatingChildren(folderChildren), at: index)
                updatedItems.insert(movedItem, at: Swift.min(index + 1, updatedItems.count))
            }

            return (updatedItems, movedItem)
        }

        return nil
    }

    func dissolvingTopLevelFolder(id: UUID) -> [LaunchItem]? {
        guard let folderIndex = firstIndex(where: { $0.id == id && $0.isFolder }) else {
            return nil
        }

        let folder = self[folderIndex]
        var updatedItems = self
        updatedItems.remove(at: folderIndex)
        updatedItems.insert(contentsOf: folder.children, at: folderIndex)
        return updatedItems
    }
}

private enum ShellAppCatalogScanner {
    static func scan() -> [LaunchItem] {
        let roots = [
            URL(filePath: "/Applications"),
            URL(filePath: "/System/Applications"),
            URL(filePath: "/System/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory),
        ]

        var seenPaths = Set<String>()
        var results: [LaunchItem] = []

        for root in roots where FileManager.default.fileExists(atPath: root.path()) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else {
                    continue
                }

                let normalizedPath = url.standardizedFileURL.path().lowercased()
                guard seenPaths.insert(normalizedPath).inserted else {
                    continue
                }

                let parent = url.deletingLastPathComponent().lastPathComponent
                let subtitle = parent == root.lastPathComponent ? nil : parent

                results.append(
                    .app(
                        title: url.deletingPathExtension().lastPathComponent,
                        subtitle: subtitle,
                        bundleURL: url
                    )
                )
            }
        }

        return results.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
}

private enum ShellAppFolderBuilder {
    static func bootstrapCatalog(from apps: [LaunchItem]) -> [LaunchItem] {
        var remainingApps = apps
        var leadingFolders: [LaunchItem] = []

        if let browsers = extractFolder(title: "Browsers", from: &remainingApps, matching: { item in
            ["arc", "brave browser", "firefox", "google chrome", "microsoft edge", "safari", "zen browser"].contains(item.title.lowercased())
        }) {
            leadingFolders.append(browsers)
        }

        if let developer = extractFolder(title: "Developer", from: &remainingApps, matching: { item in
            let name = item.title.lowercased()
            return name.contains("xcode")
                || name.contains("terminal")
                || name.contains("console")
                || name.contains("simulator")
                || name.contains("cursor")
                || name.contains("code")
                || name.contains("warp")
                || name.contains("iterm")
        }) {
            leadingFolders.append(developer)
        }

        if let utilities = extractFolder(title: "Utilities", from: &remainingApps, matching: { item in
            let name = item.title.lowercased()
            let subtitle = (item.subtitle ?? "").lowercased()
            return subtitle.contains("utilities")
                || name.contains("monitor")
                || name.contains("keychain")
                || name.contains("disk utility")
                || name.contains("screenshot")
                || name.contains("migration assistant")
                || name.contains("system information")
        }) {
            leadingFolders.append(utilities)
        }

        return leadingFolders + remainingApps
    }

    private static func extractFolder(
        title: String,
        from apps: inout [LaunchItem],
        matching: (LaunchItem) -> Bool
    ) -> LaunchItem? {
        let matches = apps.filter(matching)
        guard matches.count >= 2 else {
            return nil
        }

        let ids = Set(matches.map(\.id))
        apps.removeAll { ids.contains($0.id) }

        return .folder(
            title: title,
            children: matches.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        )
    }
}
