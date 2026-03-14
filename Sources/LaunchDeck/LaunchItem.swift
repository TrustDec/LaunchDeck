import Foundation

struct LaunchItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case app
        case folder
    }

    let id: UUID
    let title: String
    let subtitle: String?
    let kind: Kind
    let bundleURL: URL?
    let children: [LaunchItem]

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        kind: Kind,
        bundleURL: URL? = nil,
        children: [LaunchItem] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.bundleURL = bundleURL
        self.children = children
    }

    var isFolder: Bool {
        kind == .folder
    }

    var searchableText: String {
        ([title, subtitle].compactMap { $0 } + children.map(\.title))
            .joined(separator: " ")
            .lowercased()
    }

    func searchScore(for query: String, recentBundlePaths: [String]) -> LaunchDeckSearchMatchScore? {
        let normalizedTitle = title.lowercased()
        let normalizedSubtitle = subtitle?.lowercased() ?? ""
        let childMatches = children.filter { $0.title.lowercased().contains(query) }.count

        let titlePrefix = normalizedTitle.hasPrefix(query) ? 3 : 0
        let titleContains = normalizedTitle.contains(query) ? 2 : 0
        let subtitleContains = normalizedSubtitle.contains(query) ? 1 : 0
        let childContains = childMatches > 0 ? 1 : 0

        guard titlePrefix > 0 || titleContains > 0 || subtitleContains > 0 || childContains > 0 else {
            return nil
        }

        let isSystemApp = bundleURL?.path.hasPrefix("/System/Applications") == true ? 1 : 0
        let recentLaunchBonus: Int
        if let bundlePath = bundleURL?.path,
           let recentIndex = recentBundlePaths.firstIndex(of: bundlePath) {
            recentLaunchBonus = max(0, 4 - recentIndex)
        } else {
            recentLaunchBonus = 0
        }
        let titleLengthBias = max(0, 40 - normalizedTitle.count)

        return LaunchDeckSearchMatchScore(
            titlePrefix: titlePrefix,
            titleContains: titleContains,
            subtitleContains: subtitleContains,
            childContains: childContains,
            recentLaunchBonus: recentLaunchBonus,
            systemAppBonus: isSystemApp,
            titleLengthBias: titleLengthBias
        )
    }

    static func app(
        title: String,
        subtitle: String? = nil,
        bundleURL: URL? = nil
    ) -> LaunchItem {
        LaunchItem(
            title: title,
            subtitle: subtitle,
            kind: .app,
            bundleURL: bundleURL
        )
    }

    static func folder(
        title: String,
        subtitle: String? = nil,
        children: [LaunchItem]
    ) -> LaunchItem {
        LaunchItem(
            title: title,
            subtitle: subtitle,
            kind: .folder,
            children: children
        )
    }

    func updatingChildren(_ children: [LaunchItem]) -> LaunchItem {
        LaunchItem(
            id: id,
            title: title,
            subtitle: subtitle,
            kind: kind,
            bundleURL: bundleURL,
            children: children
        )
    }

    func updatingTitle(_ title: String) -> LaunchItem {
        LaunchItem(
            id: id,
            title: title,
            subtitle: subtitle,
            kind: kind,
            bundleURL: bundleURL,
            children: children
        )
    }
}

extension LaunchItem {
    static let demoCatalog: [LaunchItem] = [
        .folder(
            title: "Browsers",
            subtitle: "Fallback folder",
            children: [
                .app(title: "Safari"),
                .app(title: "Firefox"),
                .app(title: "Arc"),
            ]
        ),
        .folder(
            title: "Developer",
            subtitle: "Fallback folder",
            children: [
                .app(title: "Xcode"),
                .app(title: "Terminal"),
                .app(title: "Console"),
            ]
        ),
        .app(title: "Mail"),
        .app(title: "Notes"),
        .app(title: "Photos"),
        .app(title: "Music"),
        .app(title: "Calendar"),
        .app(title: "App Store"),
    ]
}
