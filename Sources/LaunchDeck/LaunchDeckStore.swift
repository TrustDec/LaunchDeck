import AppKit
import Foundation

@MainActor
final class LaunchDeckStore: ObservableObject {
    @Published private(set) var rootItems: [LaunchItem] = []
    @Published var query = "" {
        didSet {
            currentPage = 0
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                exitEditMode()
            }
        }
    }
    @Published var currentPage = 0
    @Published var selectedFolder: LaunchItem?
    @Published var isEditing = false
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var draggedItemID: UUID?

    private(set) var pageSize = 35

    var totalAppCount: Int {
        rootItems.reduce(into: 0) { partialResult, item in
            partialResult += item.isFolder ? item.children.count : 1
        }
    }

    var canEditLayout: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var filteredItems: [LaunchItem] {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedQuery.isEmpty else {
            return rootItems
        }

        return rootItems.compactMap { item in
            if item.isFolder {
                let matchedChildren = item.children.filter { child in
                    child.searchableText.contains(normalizedQuery)
                }

                if item.searchableText.contains(normalizedQuery) || !matchedChildren.isEmpty {
                    return .folder(
                        title: item.title,
                        subtitle: item.subtitle,
                        children: matchedChildren.isEmpty ? item.children : matchedChildren
                    )
                }

                return nil
            }

            return item.searchableText.contains(normalizedQuery) ? item : nil
        }
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

    var visibleItems: [LaunchItem] {
        guard pageCount > 0 else {
            return []
        }

        return pagedItems[currentPage]
    }

    var pageCount: Int {
        pagedItems.count
    }

    var resultCount: Int {
        filteredItems.reduce(into: 0) { partialResult, item in
            partialResult += item.isFolder ? item.children.count : 1
        }
    }

    func loadIfNeeded() async {
        guard rootItems.isEmpty, !isLoading else {
            return
        }

        await reload()
    }

    func reload() async {
        isLoading = true
        lastError = nil
        let start = Date()
        LaunchDeckDiagnostics.log("catalog scan started")

        let catalog = await Task.detached(priority: .utility) {
            AppCatalogScanner.scan()
        }.value

        LaunchDeckDiagnostics.log("catalog scan finished count=\(catalog.count) duration=\(String(format: "%.2f", Date().timeIntervalSince(start)))s")
        rootItems = AppFolderBuilder.bootstrapCatalog(from: catalog)
        if rootItems.isEmpty {
            rootItems = LaunchItem.demoCatalog
        }

        currentPage = 0
        selectedFolder = nil
        isEditing = false
        draggedItemID = nil
        isLoading = false
    }

    func activate(_ item: LaunchItem) {
        if item.isFolder {
            selectedFolder = item
            return
        }

        guard let bundleURL = item.bundleURL else {
            lastError = "This placeholder item does not point to an installed app yet."
            return
        }

        selectedFolder = nil

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { [weak self] _, error in
            guard let error else {
                return
            }

            Task { @MainActor in
                self?.lastError = error.localizedDescription
            }
        }
    }

    func closeFolder() {
        selectedFolder = nil
    }

    func selectPage(_ page: Int) {
        let clamped = min(max(page, 0), max(pageCount - 1, 0))
        guard clamped != currentPage else {
            return
        }

        currentPage = clamped
    }

    func nextPage() {
        selectPage(currentPage + 1)
    }

    func previousPage() {
        selectPage(currentPage - 1)
    }

    func updatePageCapacity(_ capacity: Int) {
        let normalized = max(capacity, 1)
        guard normalized != pageSize else {
            return
        }

        pageSize = normalized
        currentPage = min(currentPage, max(pageCount - 1, 0))
    }

    func enterEditMode() {
        guard canEditLayout else {
            lastError = "Clear search before rearranging apps."
            return
        }

        isEditing = true
        selectedFolder = nil
    }

    func exitEditMode() {
        isEditing = false
        draggedItemID = nil
    }

    func beginDragging(_ item: LaunchItem) {
        guard canEditLayout else {
            return
        }

        if !isEditing {
            enterEditMode()
        }

        draggedItemID = item.id
    }

    func completeDragging() {
        draggedItemID = nil
    }

    @discardableResult
    func dropDraggedItem(on targetID: UUID) -> Bool {
        defer {
            draggedItemID = nil
        }

        guard canEditLayout,
              let sourceID = draggedItemID,
              sourceID != targetID,
              let sourceIndex = rootItems.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = rootItems.firstIndex(where: { $0.id == targetID }) else {
            return false
        }

        let sourceItem = rootItems[sourceIndex]
        let targetItem = rootItems[targetIndex]

        if targetItem.isFolder && !sourceItem.isFolder {
            return insert(sourceItem, intoFolderAt: targetIndex, removingFrom: sourceIndex)
        }

        if !sourceItem.isFolder && !targetItem.isFolder {
            return makeFolder(with: sourceItem, at: sourceIndex, and: targetItem, at: targetIndex)
        }

        reorderItem(from: sourceIndex, to: targetIndex)
        return true
    }

    private func reorderItem(from sourceIndex: Int, to targetIndex: Int) {
        guard sourceIndex != targetIndex else {
            return
        }

        var updatedItems = rootItems
        let item = updatedItems.remove(at: sourceIndex)
        let destination = sourceIndex < targetIndex ? max(targetIndex - 1, 0) : targetIndex
        updatedItems.insert(item, at: destination)
        rootItems = updatedItems
    }

    private func insert(_ item: LaunchItem, intoFolderAt folderIndex: Int, removingFrom sourceIndex: Int) -> Bool {
        guard folderIndex != sourceIndex else {
            return false
        }

        var updatedItems = rootItems
        let sourceItem = updatedItems.remove(at: sourceIndex)
        let adjustedFolderIndex = sourceIndex < folderIndex ? folderIndex - 1 : folderIndex
        let folder = updatedItems[adjustedFolderIndex]

        guard folder.isFolder else {
            return false
        }

        let mergedChildren = (folder.children + [sourceItem]).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        updatedItems[adjustedFolderIndex] = folder.updatingChildren(mergedChildren)
        rootItems = updatedItems
        return true
    }

    private func makeFolder(with sourceItem: LaunchItem, at sourceIndex: Int, and targetItem: LaunchItem, at targetIndex: Int) -> Bool {
        guard sourceIndex != targetIndex else {
            return false
        }

        let lowerIndex = min(sourceIndex, targetIndex)
        let upperIndex = max(sourceIndex, targetIndex)
        let sourceFirst = lowerIndex == sourceIndex
        let sortedChildren = [sourceItem, targetItem].sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        let folderTitle = suggestedFolderTitle(primary: sourceFirst ? sourceItem : targetItem, secondary: sourceFirst ? targetItem : sourceItem)
        let folder = LaunchItem.folder(title: folderTitle, children: sortedChildren)

        var updatedItems = rootItems
        updatedItems.remove(at: upperIndex)
        updatedItems.remove(at: lowerIndex)
        updatedItems.insert(folder, at: lowerIndex)
        rootItems = updatedItems
        return true
    }

    private func suggestedFolderTitle(primary: LaunchItem, secondary: LaunchItem) -> String {
        let primaryName = primary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondaryName = secondary.title.trimmingCharacters(in: .whitespacesAndNewlines)

        if let primaryWord = primaryName.split(separator: " ").first,
           let secondaryWord = secondaryName.split(separator: " ").first,
           primaryWord.caseInsensitiveCompare(String(secondaryWord)) == .orderedSame {
            return String(primaryWord)
        }

        return "Folder"
    }
}

private enum AppCatalogScanner {
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

private enum AppFolderBuilder {
    static func bootstrapCatalog(from apps: [LaunchItem]) -> [LaunchItem] {
        var remainingApps = apps
        var leadingFolders: [LaunchItem] = []

        if let browsers = extractFolder(
            title: "Browsers",
            subtitle: nil,
            from: &remainingApps,
            matching: { item in
                [
                    "arc",
                    "brave browser",
                    "firefox",
                    "google chrome",
                    "microsoft edge",
                    "orion",
                    "safari",
                    "zen browser",
                ].contains(item.title.lowercased())
            }
        ) {
            leadingFolders.append(browsers)
        }

        if let developer = extractFolder(
            title: "Developer",
            subtitle: nil,
            from: &remainingApps,
            matching: { item in
                let name = item.title.lowercased()
                return name.contains("xcode")
                    || name.contains("terminal")
                    || name.contains("console")
                    || name.contains("simulator")
                    || name.contains("instrument")
                    || name.contains("cursor")
                    || name.contains("code")
                    || name.contains("warp")
                    || name.contains("iterm")
            }
        ) {
            leadingFolders.append(developer)
        }

        if let utilities = extractFolder(
            title: "Utilities",
            subtitle: nil,
            from: &remainingApps,
            matching: { item in
                let name = item.title.lowercased()
                let subtitle = (item.subtitle ?? "").lowercased()
                return subtitle.contains("utilities")
                    || name.contains("monitor")
                    || name.contains("keychain")
                    || name.contains("disk utility")
                    || name.contains("screenshot")
                    || name.contains("migration assistant")
                    || name.contains("system information")
            }
        ) {
            leadingFolders.append(utilities)
        }

        return leadingFolders + remainingApps
    }

    private static func extractFolder(
        title: String,
        subtitle: String?,
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
            subtitle: subtitle,
            children: matches.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        )
    }
}
