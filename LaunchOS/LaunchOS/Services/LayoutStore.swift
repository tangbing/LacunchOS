import Foundation

struct AppliedLauncherLayout: Sendable {
    let apps: [AppRecord]
    let folders: [LauncherFolder]
    let orderedItemIDs: [LauncherItem.ID]
}

struct LayoutStore: Sendable {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    func load() async throws -> LauncherLayoutSnapshot {
        try await load(from: fileURL)
    }

    func load(from url: URL) async throws -> LauncherLayoutSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder.layoutDecoder.decode(LauncherLayoutSnapshot.self, from: data)
    }

    func save(_ snapshot: LauncherLayoutSnapshot) async throws {
        try await save(snapshot, to: fileURL)
    }

    func save(_ snapshot: LauncherLayoutSnapshot, to url: URL) async throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var snapshot = snapshot
        snapshot.updatedAt = Date()

        let data = try JSONEncoder.layoutEncoder.encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }

    func applying(_ snapshot: LauncherLayoutSnapshot, to scannedApps: [AppRecord]) -> AppliedLauncherLayout {
        var appsByID = Dictionary(uniqueKeysWithValues: scannedApps.map { ($0.id, $0) })
        var orderedApps: [AppRecord] = []

        for appID in snapshot.orderedAppIDs {
            guard var app = appsByID.removeValue(forKey: appID) else {
                continue
            }

            apply(snapshot.appStates[appID], to: &app)
            orderedApps.append(app)
        }

        let newApps = appsByID.values.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        let apps = orderedApps + newApps.map { app in
            var app = app
            apply(snapshot.appStates[app.id], to: &app)
            return app
        }

        let folders = sanitizedFolders(snapshot.folders, availableAppIDs: Set(apps.map(\.id)))
        let orderedItemIDs = sanitizedOrderedItemIDs(
            snapshot.orderedItemIDs.isEmpty ? snapshot.orderedAppIDs : snapshot.orderedItemIDs,
            apps: apps,
            folders: folders
        )

        return AppliedLauncherLayout(apps: apps, folders: folders, orderedItemIDs: orderedItemIDs)
    }

    func snapshot(
        apps: [AppRecord],
        folders: [LauncherFolder],
        orderedItemIDs: [LauncherItem.ID],
        currentPage: Int,
        settings: LayoutSettings
    ) -> LauncherLayoutSnapshot {
        let states = Dictionary(uniqueKeysWithValues: apps.map { app in
            (
                app.id,
                AppLayoutState(
                    alias: app.alias,
                    isHidden: app.isHidden,
                    lastOpenedAt: app.lastOpenedAt
                )
            )
        })

        return LauncherLayoutSnapshot(
            version: 3,
            orderedAppIDs: apps.map(\.id),
            orderedItemIDs: orderedItemIDs,
            folders: folders,
            appStates: states,
            currentPage: max(0, currentPage),
            settings: settings
        )
    }

    private func apply(_ state: AppLayoutState?, to app: inout AppRecord) {
        guard let state else {
            return
        }

        app.alias = state.alias
        app.isHidden = state.isHidden
        app.lastOpenedAt = state.lastOpenedAt
    }

    private func sanitizedFolders(
        _ folders: [LauncherFolder],
        availableAppIDs: Set<AppRecord.ID>
    ) -> [LauncherFolder] {
        folders.compactMap { folder in
            var seenAppIDs: Set<AppRecord.ID> = []
            let appIDs = folder.appIDs.filter { appID in
                guard availableAppIDs.contains(appID), !seenAppIDs.contains(appID) else {
                    return false
                }

                seenAppIDs.insert(appID)
                return true
            }

            guard appIDs.count >= 2 else {
                return nil
            }

            var folder = folder
            folder.appIDs = appIDs
            return folder
        }
    }

    private func sanitizedOrderedItemIDs(
        _ savedItemIDs: [LauncherItem.ID],
        apps: [AppRecord],
        folders: [LauncherFolder]
    ) -> [LauncherItem.ID] {
        let folderedAppIDs = Set(folders.flatMap(\.appIDs))
        let topLevelAppIDs = apps
            .filter { !$0.isHidden && !folderedAppIDs.contains($0.id) }
            .map(\.id)
        let folderIDs = folders.map(\.id)
        let validItemIDs = Set(topLevelAppIDs + folderIDs)
        var usedItemIDs: Set<LauncherItem.ID> = []
        var orderedItemIDs: [LauncherItem.ID] = []

        for itemID in savedItemIDs where validItemIDs.contains(itemID) && !usedItemIDs.contains(itemID) {
            orderedItemIDs.append(itemID)
            usedItemIDs.insert(itemID)
        }

        for folderID in folderIDs where !usedItemIDs.contains(folderID) {
            orderedItemIDs.append(folderID)
            usedItemIDs.insert(folderID)
        }

        for appID in topLevelAppIDs where !usedItemIDs.contains(appID) {
            orderedItemIDs.append(appID)
            usedItemIDs.insert(appID)
        }

        return orderedItemIDs
    }

    private static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

        return appSupport
            .appendingPathComponent("LaunchOS", isDirectory: true)
            .appendingPathComponent("layout.json")
    }
}

private extension JSONDecoder {
    static var layoutDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var layoutEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
