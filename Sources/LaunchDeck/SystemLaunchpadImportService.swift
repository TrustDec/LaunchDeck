import AppKit
import Foundation
import SQLite3

enum SystemLaunchpadImportService {
    static func importItems() -> [LaunchItem]? {
        for url in candidateDatabaseURLs() {
            guard let items = loadItems(from: url), !items.isEmpty else {
                continue
            }
            LaunchDeckDiagnostics.log("launchpad import succeeded path=\(url.path()) count=\(items.count)")
            return items
        }

        LaunchDeckDiagnostics.log("launchpad import unavailable")
        return nil
    }

    private static func candidateDatabaseURLs() -> [URL] {
        let roots = [
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Dock", directoryHint: .isDirectory),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/com.apple.dock", directoryHint: .isDirectory),
        ]

        var results: [URL] = []

        for root in roots where FileManager.default.fileExists(atPath: root.path()) {
            guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
                continue
            }

            results.append(contentsOf: files.filter { $0.pathExtension == "db" })
        }

        return results.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func loadItems(from databaseURL: URL) -> [LaunchItem]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        let tables = fetchTables(in: db)
        guard tables.contains("apps"), tables.contains("items") else {
            return nil
        }

        let appsByRowID = fetchApps(in: db)
        let groupsByRowID = tables.contains("groups") ? fetchGroups(in: db) : [:]
        let itemRows = fetchItemRows(in: db)

        guard !appsByRowID.isEmpty, !itemRows.isEmpty else {
            return nil
        }

        let childrenByParent = Dictionary(grouping: itemRows, by: \.parentID)
        let topLevel = (childrenByParent[0] ?? []) + (childrenByParent[-1] ?? [])
        let orderedTopLevel = topLevel.sorted { $0.ordering < $1.ordering }

        let mapped = orderedTopLevel.compactMap { row in
            materialize(row: row, appsByRowID: appsByRowID, groupsByRowID: groupsByRowID, childrenByParent: childrenByParent)
        }

        return mapped.isEmpty ? nil : mapped
    }

    private static func fetchTables(in db: OpaquePointer?) -> Set<String> {
        let sql = "SELECT name FROM sqlite_master WHERE type='table';"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        var tables = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                tables.insert(String(cString: cString))
            }
        }
        return tables
    }

    private static func fetchApps(in db: OpaquePointer?) -> [Int64: LaunchItem] {
        let sql = "SELECT rowid, title, bundleid FROM apps;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return [:]
        }

        var apps: [Int64: LaunchItem] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(statement, 0)
            let title = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "App"
            let bundleID = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            let bundleURL = bundleID.flatMap(resolveAppURL(bundleIdentifier:))
            apps[rowID] = LaunchItem.app(title: title, subtitle: nil, bundleURL: bundleURL)
        }
        return apps
    }

    private static func fetchGroups(in db: OpaquePointer?) -> [Int64: String] {
        let sql = "SELECT rowid, title FROM groups;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return [:]
        }

        var groups: [Int64: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(statement, 0)
            let title = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "Folder"
            groups[rowID] = title
        }
        return groups
    }

    private static func fetchItemRows(in db: OpaquePointer?) -> [LaunchpadDBRow] {
        let orderingColumn = columnExists(named: "ordering", table: "items", in: db) ? "ordering" : "0"
        let parentColumn = columnExists(named: "parent_id", table: "items", in: db) ? "parent_id" : "0"
        let sql = "SELECT rowid, \(parentColumn), \(orderingColumn) FROM items;"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        var rows: [LaunchpadDBRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(
                LaunchpadDBRow(
                    rowID: sqlite3_column_int64(statement, 0),
                    parentID: sqlite3_column_int64(statement, 1),
                    ordering: sqlite3_column_int64(statement, 2)
                )
            )
        }
        return rows
    }

    private static func columnExists(named column: String, table: String, in db: OpaquePointer?) -> Bool {
        let sql = "PRAGMA table_info(\(table));"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 1), String(cString: cString) == column {
                return true
            }
        }
        return false
    }

    private static func materialize(
        row: LaunchpadDBRow,
        appsByRowID: [Int64: LaunchItem],
        groupsByRowID: [Int64: String],
        childrenByParent: [Int64: [LaunchpadDBRow]]
    ) -> LaunchItem? {
        if let app = appsByRowID[row.rowID] {
            return app
        }

        guard let title = groupsByRowID[row.rowID] else {
            return nil
        }

        let children = (childrenByParent[row.rowID] ?? [])
            .sorted { $0.ordering < $1.ordering }
            .compactMap {
                materialize(row: $0, appsByRowID: appsByRowID, groupsByRowID: groupsByRowID, childrenByParent: childrenByParent)
            }

        guard !children.isEmpty else {
            return nil
        }

        return LaunchItem.folder(title: title, children: children)
    }

    private static func resolveAppURL(bundleIdentifier: String) -> URL? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return appURL
    }
}

private struct LaunchpadDBRow {
    let rowID: Int64
    let parentID: Int64
    let ordering: Int64
}
