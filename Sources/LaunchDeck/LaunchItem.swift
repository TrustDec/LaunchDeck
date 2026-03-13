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
