import Foundation

struct LauncherLayoutSnapshot: Codable, Equatable, Sendable {
    var version = 3
    var orderedAppIDs: [AppRecord.ID] = []
    var orderedItemIDs: [String] = []
    var folders: [LauncherFolder] = []
    var appStates: [AppRecord.ID: AppLayoutState] = [:]
    var currentPage = 0
    var settings = LayoutSettings()
    var updatedAt = Date()

    static let empty = LauncherLayoutSnapshot()

    init(
        version: Int = 3,
        orderedAppIDs: [AppRecord.ID] = [],
        orderedItemIDs: [String] = [],
        folders: [LauncherFolder] = [],
        appStates: [AppRecord.ID: AppLayoutState] = [:],
        currentPage: Int = 0,
        settings: LayoutSettings = LayoutSettings(),
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.orderedAppIDs = orderedAppIDs
        self.orderedItemIDs = orderedItemIDs
        self.folders = folders
        self.appStates = appStates
        self.currentPage = currentPage
        self.settings = settings
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        orderedAppIDs = try container.decodeIfPresent([AppRecord.ID].self, forKey: .orderedAppIDs) ?? []
        orderedItemIDs = try container.decodeIfPresent([String].self, forKey: .orderedItemIDs) ?? []
        folders = try container.decodeIfPresent([LauncherFolder].self, forKey: .folders) ?? []
        appStates = try container.decodeIfPresent([AppRecord.ID: AppLayoutState].self, forKey: .appStates) ?? [:]
        currentPage = try container.decodeIfPresent(Int.self, forKey: .currentPage) ?? 0
        settings = try container.decodeIfPresent(LayoutSettings.self, forKey: .settings) ?? LayoutSettings()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

struct AppLayoutState: Codable, Equatable, Sendable {
    var alias: String?
    var isHidden = false
    var lastOpenedAt: Date?
}

struct LauncherFolder: Codable, Equatable, Hashable, Identifiable, Sendable {
    static let idPrefix = "folder:"

    var id: String
    var name: String
    var appIDs: [AppRecord.ID]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = "\(idPrefix)\(UUID().uuidString)",
        name: String,
        appIDs: [AppRecord.ID],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct LayoutSettings: Codable, Equatable, Sendable {
    enum BrowsingMode: String, Codable, CaseIterable, Identifiable, Sendable {
        case paged
        case verticalScroll

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .paged:
                String(localized: "Paged")
            case .verticalScroll:
                String(localized: "Vertical Scroll")
            }
        }
    }

    static let minimumCustomColumns = 3
    static let maximumCustomColumns = 12
    static let minimumCustomRows = 2
    static let maximumCustomRows = 8

    var browsingMode: BrowsingMode = .paged
    var remembersLastPage = true
    var usesCustomGrid = false
    var customColumnCount = 7
    var customRowCount = 5
    var customApplicationDirectoryPaths: [String] = []
    var lastKnownColumns = 1
    var lastKnownRows = 1
    var lastKnownItemsPerPage = 1

    init(
        browsingMode: BrowsingMode = .paged,
        remembersLastPage: Bool = true,
        usesCustomGrid: Bool = false,
        customColumnCount: Int = 7,
        customRowCount: Int = 5,
        customApplicationDirectoryPaths: [String] = [],
        lastKnownColumns: Int = 1,
        lastKnownRows: Int = 1,
        lastKnownItemsPerPage: Int = 1
    ) {
        self.browsingMode = browsingMode
        self.remembersLastPage = remembersLastPage
        self.usesCustomGrid = usesCustomGrid
        self.customColumnCount = customColumnCount
        self.customRowCount = customRowCount
        self.customApplicationDirectoryPaths = customApplicationDirectoryPaths
        self.lastKnownColumns = lastKnownColumns
        self.lastKnownRows = lastKnownRows
        self.lastKnownItemsPerPage = lastKnownItemsPerPage
        sanitize()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        browsingMode = try container.decodeIfPresent(BrowsingMode.self, forKey: .browsingMode) ?? .paged
        remembersLastPage = try container.decodeIfPresent(Bool.self, forKey: .remembersLastPage) ?? true
        usesCustomGrid = try container.decodeIfPresent(Bool.self, forKey: .usesCustomGrid) ?? false
        customColumnCount = try container.decodeIfPresent(Int.self, forKey: .customColumnCount) ?? 7
        customRowCount = try container.decodeIfPresent(Int.self, forKey: .customRowCount) ?? 5
        customApplicationDirectoryPaths = try container.decodeIfPresent(
            [String].self,
            forKey: .customApplicationDirectoryPaths
        ) ?? []
        lastKnownColumns = try container.decodeIfPresent(Int.self, forKey: .lastKnownColumns) ?? 1
        lastKnownRows = try container.decodeIfPresent(Int.self, forKey: .lastKnownRows) ?? 1
        lastKnownItemsPerPage = try container.decodeIfPresent(Int.self, forKey: .lastKnownItemsPerPage) ?? 1
        sanitize()
    }

    mutating func sanitize() {
        customColumnCount = min(
            max(customColumnCount, Self.minimumCustomColumns),
            Self.maximumCustomColumns
        )
        customRowCount = min(
            max(customRowCount, Self.minimumCustomRows),
            Self.maximumCustomRows
        )
        lastKnownColumns = max(1, lastKnownColumns)
        lastKnownRows = max(1, lastKnownRows)
        lastKnownItemsPerPage = max(1, lastKnownItemsPerPage)
        customApplicationDirectoryPaths = Self.normalizedDirectoryPaths(customApplicationDirectoryPaths)
    }

    func sanitized() -> LayoutSettings {
        var copy = self
        copy.sanitize()
        return copy
    }

    nonisolated static func normalizedDirectoryPaths(_ paths: [String]) -> [String] {
        var seenPaths: Set<String> = []
        var normalizedPaths: [String] = []

        for path in paths {
            let expandedPath = (path as NSString).expandingTildeInPath
            let normalizedPath = (expandedPath as NSString)
                .standardizingPath
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !normalizedPath.isEmpty, seenPaths.insert(normalizedPath).inserted else {
                continue
            }

            normalizedPaths.append(normalizedPath)
        }

        return normalizedPaths
    }
}
