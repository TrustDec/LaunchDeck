import AppKit
import Foundation

struct LaunchDeckSearchMatchScore: Comparable {
    let titlePrefix: Int
    let titleContains: Int
    let subtitleContains: Int
    let childContains: Int
    let recentLaunchBonus: Int
    let systemAppBonus: Int
    let titleLengthBias: Int

    static func < (lhs: LaunchDeckSearchMatchScore, rhs: LaunchDeckSearchMatchScore) -> Bool {
        [
            lhs.titlePrefix,
            lhs.titleContains,
            lhs.subtitleContains,
            lhs.childContains,
            lhs.recentLaunchBonus,
            lhs.systemAppBonus,
            lhs.titleLengthBias,
        ].lexicographicallyPrecedes([
            rhs.titlePrefix,
            rhs.titleContains,
            rhs.subtitleContains,
            rhs.childContains,
            rhs.recentLaunchBonus,
            rhs.systemAppBonus,
            rhs.titleLengthBias,
        ])
    }
}

@MainActor
final class LaunchDeckShellStore: ObservableObject {
    private enum DefaultsKey {
        static let compactMode = "LaunchDeck.compactMode"
        static let hiddenItems = "LaunchDeck.hiddenItems"
        static let recentLaunches = "LaunchDeck.recentLaunches"
    }

    @Published private(set) var items: [LaunchItem] = []
    @Published var query = ""
    @Published var selectedFolder: LaunchItem?
    @Published private(set) var isLoading = false
    @Published var currentPage = 0
    @Published var compactMode = UserDefaults.standard.bool(forKey: DefaultsKey.compactMode)
    @Published private(set) var hiddenItems: [LaunchItem]
    @Published var selectedSearchResultID: UUID?

    private let persistence: LaunchDeckPersistenceController
    private(set) var pageSize = 30
    private var recentLaunchBundlePaths: [String] = UserDefaults.standard.stringArray(forKey: DefaultsKey.recentLaunches) ?? []

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

        return items
            .compactMap { item -> (LaunchItem, LaunchDeckSearchMatchScore)? in
                guard let score = item.searchScore(for: normalized, recentBundlePaths: recentLaunchBundlePaths) else {
                    return nil
                }
                return (item, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
            }
            .map(\.0)
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
        if item.isFolder {
            guard let topLevelFolder = items.first(where: { $0.id == item.id && $0.isFolder }) else {
                return
            }
            if isSearching {
                query = ""
                selectedSearchResultID = nil
            }
            selectedFolder = topLevelFolder
            return
        }

        guard let bundleURL = item.bundleURL else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
        rememberRecentLaunch(for: bundleURL.path)
    }

    func revealInFinder(_ item: LaunchItem) {
        guard let bundleURL = item.bundleURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }

    func revealSelectedSearchResultInFinder() {
        guard let item = primarySearchResult else {
            return
        }
        revealInFinder(item)
    }

    func closeFolder() {
        selectedFolder = nil
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
            self.selectedSearchResultID = filteredItems.first?.id
            return
        }

        let nextIndex = min(currentIndex + 1, filteredItems.count - 1)
        self.selectedSearchResultID = filteredItems[nextIndex].id
    }

    func selectPreviousSearchResult() {
        guard isSearching, !filteredItems.isEmpty else {
            return
        }

        guard let selectedSearchResultID,
              let currentIndex = filteredItems.firstIndex(where: { $0.id == selectedSearchResultID })
        else {
            self.selectedSearchResultID = filteredItems.first?.id
            return
        }

        let previousIndex = max(currentIndex - 1, 0)
        self.selectedSearchResultID = filteredItems[previousIndex].id
    }

    private func persistCurrentLayout() {
        persistence.saveLayout(items: items)
        persistence.saveSnapshot(items: items)
    }

    private func rememberRecentLaunch(for bundlePath: String) {
        recentLaunchBundlePaths.removeAll { $0 == bundlePath }
        recentLaunchBundlePaths.insert(bundlePath, at: 0)
        recentLaunchBundlePaths = Array(recentLaunchBundlePaths.prefix(12))
        UserDefaults.standard.set(recentLaunchBundlePaths, forKey: DefaultsKey.recentLaunches)
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
